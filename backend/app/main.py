import json
import os
import re
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import asyncpg
import httpx
from fastapi import FastAPI, HTTPException, Request
from fastapi.responses import JSONResponse
from fastapi.staticfiles import StaticFiles

KENTEKEN_RE = re.compile(r"^[A-Z0-9]{6}$")

DEFAULT_RDW_DATASETS = [
    {"name": "Gekentekende voertuigen", "resource": "m9d7-ebf2", "required": True},
    {"name": "Gekentekende voertuigen - brandstof", "resource": "8ys7-d773", "required": False},
    {"name": "Gekentekende voertuigen - carrosserie", "resource": "6h3n-xc5s", "required": False},
    {"name": "Gekentekende voertuigen - carrosserie specifiek", "resource": "jhie-znh9", "required": False},
    {"name": "Gekentekende voertuigen - assen", "resource": "3huj-srit", "required": False},
]


def env_bool(name: str, default: bool = False) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    return value.strip().lower() in {"1", "true", "yes", "y", "on"}


def normalize_kenteken(value: str) -> str:
    return re.sub(r"[^A-Za-z0-9]", "", value or "").upper()


def validate_kenteken(value: str) -> str:
    normalized = normalize_kenteken(value)
    if not KENTEKEN_RE.match(normalized):
        raise HTTPException(
            status_code=400,
            detail="Ongeldig kenteken. Voer een Nederlands kenteken in met 6 letters/cijfers, bijvoorbeeld AB123C of 12ABC3.",
        )
    return normalized


def load_rdw_datasets() -> list[dict[str, Any]]:
    raw = os.getenv("RDW_DATASETS_JSON")
    if not raw:
        return DEFAULT_RDW_DATASETS
    try:
        parsed = json.loads(raw)
        if not isinstance(parsed, list):
            raise ValueError("RDW_DATASETS_JSON must be a JSON array")
        datasets: list[dict[str, Any]] = []
        for item in parsed:
            if not isinstance(item, dict) or not item.get("resource"):
                raise ValueError("Each dataset must be an object with a resource field")
            datasets.append(
                {
                    "name": str(item.get("name") or item["resource"]),
                    "resource": str(item["resource"]),
                    "required": bool(item.get("required", False)),
                }
            )
        return datasets or DEFAULT_RDW_DATASETS
    except Exception as exc:
        print(f"Invalid RDW_DATASETS_JSON, using defaults: {exc}", flush=True)
        return DEFAULT_RDW_DATASETS


async def init_connection(conn: asyncpg.Connection) -> None:
    await conn.set_type_codec(
        "jsonb",
        encoder=json.dumps,
        decoder=json.loads,
        schema="pg_catalog",
        format="text",
    )
    await conn.set_type_codec(
        "json",
        encoder=json.dumps,
        decoder=json.loads,
        schema="pg_catalog",
        format="text",
    )


async def create_schema(pool: asyncpg.Pool) -> None:
    async with pool.acquire() as conn:
        await conn.execute(
            """
            CREATE TABLE IF NOT EXISTS users (
                id UUID PRIMARY KEY,
                email TEXT UNIQUE,
                password_hash TEXT,
                role TEXT NOT NULL DEFAULT 'user',
                profile JSONB,
                created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
            );
            """
        )
        await conn.execute(
            """
            CREATE TABLE IF NOT EXISTS rdw_cache (
                id UUID PRIMARY KEY,
                kenteken TEXT NOT NULL UNIQUE,
                payload JSONB NOT NULL,
                fetched_at TIMESTAMPTZ NOT NULL,
                source TEXT NOT NULL DEFAULT 'rdw-realtime',
                ttl_seconds INTEGER
            );
            """
        )
        await conn.execute("CREATE INDEX IF NOT EXISTS idx_rdw_cache_kenteken ON rdw_cache (kenteken);")
        await conn.execute("CREATE INDEX IF NOT EXISTS idx_rdw_cache_fetched_at ON rdw_cache (fetched_at);")


async def get_cached_payload(pool: asyncpg.Pool, kenteken: str, ttl_seconds: int) -> dict[str, Any] | None:
    if ttl_seconds <= 0:
        return None
    async with pool.acquire() as conn:
        row = await conn.fetchrow(
            """
            SELECT payload, fetched_at
            FROM rdw_cache
            WHERE kenteken = $1
            LIMIT 1;
            """,
            kenteken,
        )
    if not row:
        return None
    fetched_at = row["fetched_at"]
    if fetched_at.tzinfo is None:
        fetched_at = fetched_at.replace(tzinfo=timezone.utc)
    age_seconds = (datetime.now(timezone.utc) - fetched_at).total_seconds()
    if age_seconds > ttl_seconds:
        return None
    payload = row["payload"]
    if isinstance(payload, str):
        payload = json.loads(payload)
    payload["cache"] = {"enabled": True, "hit": True, "ttl_seconds": ttl_seconds}
    return payload


async def save_cached_payload(pool: asyncpg.Pool, kenteken: str, payload: dict[str, Any], ttl_seconds: int) -> None:
    async with pool.acquire() as conn:
        await conn.execute(
            """
            INSERT INTO rdw_cache (id, kenteken, payload, fetched_at, source, ttl_seconds)
            VALUES (gen_random_uuid(), $1, $2::jsonb, NOW(), 'rdw-realtime', $3)
            ON CONFLICT (kenteken)
            DO UPDATE SET
                payload = EXCLUDED.payload,
                fetched_at = EXCLUDED.fetched_at,
                source = EXCLUDED.source,
                ttl_seconds = EXCLUDED.ttl_seconds;
            """,
            kenteken,
            payload,
            ttl_seconds,
        )


async def fetch_rdw_dataset(
    client: httpx.AsyncClient,
    base_url: str,
    dataset: dict[str, Any],
    kenteken: str,
    app_token: str | None,
) -> dict[str, Any]:
    resource = dataset["resource"]
    url = f"{base_url.rstrip('/')}/resource/{resource}.json"
    headers = {}
    if app_token:
        headers["X-App-Token"] = app_token
    response = await client.get(
        url,
        params={"kenteken": kenteken, "$limit": "500"},
        headers=headers,
    )
    if response.status_code == 429:
        raise HTTPException(status_code=429, detail="RDW Open Data rate limit bereikt. Probeer het later opnieuw.")
    response.raise_for_status()
    data = response.json()
    if not isinstance(data, list):
        data = [data]
    return {
        "name": dataset["name"],
        "resource": resource,
        "records": data,
        "record_count": len(data),
    }


async def fetch_rdw_payload(kenteken: str) -> dict[str, Any]:
    base_url = os.getenv("RDW_BASE_URL", "https://opendata.rdw.nl")
    app_token = os.getenv("RDW_APP_TOKEN") or None
    timeout_seconds = float(os.getenv("RDW_TIMEOUT_SECONDS", "12"))
    datasets = load_rdw_datasets()

    fetched_at = datetime.now(timezone.utc).isoformat()
    results: list[dict[str, Any]] = []
    errors: list[dict[str, str]] = []

    async with httpx.AsyncClient(timeout=timeout_seconds) as client:
        for dataset in datasets:
            try:
                results.append(await fetch_rdw_dataset(client, base_url, dataset, kenteken, app_token))
            except HTTPException:
                raise
            except httpx.TimeoutException:
                error = {"name": dataset["name"], "resource": dataset["resource"], "error": "Timeout bij RDW Open Data API."}
                if dataset.get("required"):
                    raise HTTPException(status_code=504, detail="Timeout bij RDW Open Data API. Probeer het later opnieuw.")
                errors.append(error)
            except httpx.HTTPStatusError as exc:
                status = exc.response.status_code
                error = {
                    "name": dataset["name"],
                    "resource": dataset["resource"],
                    "error": f"RDW API gaf HTTP {status} terug.",
                }
                if dataset.get("required"):
                    raise HTTPException(status_code=502, detail=f"RDW Open Data API fout (HTTP {status}).")
                errors.append(error)
            except Exception as exc:
                error = {"name": dataset["name"], "resource": dataset["resource"], "error": str(exc)}
                if dataset.get("required"):
                    raise HTTPException(status_code=502, detail="RDW Open Data API kon niet worden uitgelezen.")
                errors.append(error)

    total_records = sum(item["record_count"] for item in results)
    if total_records == 0:
        raise HTTPException(status_code=404, detail="Geen RDW Open Data gevonden voor dit kenteken.")

    return {
        "kenteken": kenteken,
        "fetched_at": fetched_at,
        "source": "rdw-realtime",
        "cache": {"enabled": False, "hit": False, "ttl_seconds": None},
        "summary": {
            "dataset_count": len(results),
            "record_count": total_records,
            "error_count": len(errors),
        },
        "datasets": results,
        "dataset_errors": errors,
    }


@asynccontextmanager
async def lifespan(app: FastAPI):
    database_url = os.getenv("DATABASE_URL")
    app.state.db_pool = None
    if database_url:
        try:
            pool = await asyncpg.create_pool(
                dsn=database_url,
                min_size=1,
                max_size=int(os.getenv("DB_POOL_MAX_SIZE", "5")),
                init=init_connection,
            )
            await create_schema(pool)
            app.state.db_pool = pool
            print("Connected to Postgres and ensured schema exists.", flush=True)
        except Exception as exc:
            app.state.db_pool = None
            print(f"Postgres unavailable; continuing with cache disabled: {exc}", flush=True)
    else:
        print("DATABASE_URL not set; continuing with cache disabled.", flush=True)

    yield

    pool = getattr(app.state, "db_pool", None)
    if pool:
        await pool.close()


app = FastAPI(title="RDW Kenteken Open Data", version="1.0.0", lifespan=lifespan)


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/api/rdw/{kenteken}")
async def lookup_kenteken(kenteken: str, request: Request) -> JSONResponse:
    normalized = validate_kenteken(kenteken)
    pool = getattr(request.app.state, "db_pool", None)
    cache_enabled = env_bool("RDW_CACHE_ENABLED", False) and pool is not None
    ttl_seconds = int(os.getenv("RDW_CACHE_TTL_SECONDS", "3600"))

    if cache_enabled:
        cached = await get_cached_payload(pool, normalized, ttl_seconds)
        if cached is not None:
            return JSONResponse(cached)

    payload = await fetch_rdw_payload(normalized)
    payload["cache"] = {"enabled": cache_enabled, "hit": False, "ttl_seconds": ttl_seconds if cache_enabled else None}

    if cache_enabled:
        try:
            await save_cached_payload(pool, normalized, payload, ttl_seconds)
        except Exception as exc:
            print(f"Unable to save RDW cache for {normalized}: {exc}", flush=True)

    return JSONResponse(payload)


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException) -> JSONResponse:
    return JSONResponse(status_code=exc.status_code, content={"detail": exc.detail})


static_dir = Path(__file__).resolve().parent.parent / "static"
app.mount("/", StaticFiles(directory=str(static_dir), html=True, check_dir=False), name="static")
