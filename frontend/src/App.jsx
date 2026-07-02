import { useMemo, useState } from 'react';

function normalizeKenteken(value) {
  return (value || '').replace(/[^a-zA-Z0-9]/g, '').toUpperCase();
}

function isValidKenteken(value) {
  return /^[A-Z0-9]{6}$/.test(normalizeKenteken(value));
}

function labelForKey(key) {
  return key
    .replace(/_/g, ' ')
    .replace(/\b\w/g, (char) => char.toUpperCase());
}

function formatValue(value) {
  if (value === null || value === undefined || value === '') {
    return '—';
  }
  if (typeof value === 'object') {
    return JSON.stringify(value);
  }
  return String(value);
}

function DatasetRecords({ dataset }) {
  if (!dataset.records || dataset.records.length === 0) {
    return <p className="muted">Geen records in deze RDW dataset.</p>;
  }

  return (
    <div className="records">
      {dataset.records.map((record, index) => (
        <div className="record-card" key={`${dataset.resource}-${index}`}>
          {dataset.records.length > 1 && <div className="record-title">Record {index + 1}</div>}
          <dl className="field-grid">
            {Object.entries(record).map(([key, value]) => (
              <div className="field-row" key={key}>
                <dt>{labelForKey(key)}</dt>
                <dd>{formatValue(value)}</dd>
              </div>
            ))}
          </dl>
        </div>
      ))}
    </div>
  );
}

function Results({ result }) {
  const fetched = result?.fetched_at ? new Date(result.fetched_at) : null;

  return (
    <section className="panel results-panel" aria-live="polite">
      <div className="results-header">
        <div>
          <p className="eyebrow">Resultaat</p>
          <h2>{result.kenteken}</h2>
        </div>
        <div className="meta-box">
          <span>{result.summary?.record_count ?? 0} record(s)</span>
          <span>{result.summary?.dataset_count ?? 0} dataset(s)</span>
        </div>
      </div>

      <div className="timestamp">
        Opgehaald: {fetched ? fetched.toLocaleString('nl-NL') : 'onbekend'}
        {result.cache?.enabled && (
          <span className={result.cache.hit ? 'cache hit' : 'cache'}>
            {result.cache.hit ? ' uit cache' : ' realtime opgehaald'}
          </span>
        )}
      </div>

      {result.dataset_errors?.length > 0 && (
        <div className="warning">
          <strong>Let op:</strong> sommige optionele RDW datasets konden niet worden opgehaald.
          <ul>
            {result.dataset_errors.map((item) => (
              <li key={item.resource}>{item.name}: {item.error}</li>
            ))}
          </ul>
        </div>
      )}

      <div className="dataset-list">
        {result.datasets.map((dataset) => (
          <details className="dataset" key={dataset.resource} open>
            <summary>
              <span>{dataset.name}</span>
              <small>{dataset.record_count} record(s)</small>
            </summary>
            <DatasetRecords dataset={dataset} />
          </details>
        ))}
      </div>

      <details className="raw-json">
        <summary>Raw JSON bekijken</summary>
        <pre>{JSON.stringify(result, null, 2)}</pre>
      </details>
    </section>
  );
}

export default function App() {
  const [kenteken, setKenteken] = useState('');
  const [result, setResult] = useState(null);
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);

  const normalized = useMemo(() => normalizeKenteken(kenteken), [kenteken]);
  const valid = useMemo(() => isValidKenteken(kenteken), [kenteken]);

  async function handleSubmit(event) {
    event.preventDefault();
    setError('');
    setResult(null);

    if (!valid) {
      setError('Ongeldig kenteken. Gebruik 6 letters/cijfers, bijvoorbeeld AB123C of 12ABC3. Streepjes en spaties mogen ook worden ingevoerd.');
      return;
    }

    setLoading(true);
    try {
      const response = await fetch(`/api/rdw/${encodeURIComponent(normalized)}`);
      const data = await response.json().catch(() => ({}));
      if (!response.ok) {
        throw new Error(data.detail || 'Er ging iets mis bij het ophalen van RDW Open Data.');
      }
      setResult(data);
    } catch (err) {
      setError(err.message || 'Er ging iets mis bij het ophalen van RDW Open Data.');
    } finally {
      setLoading(false);
    }
  }

  return (
    <main className="page">
      <section className="hero">
        <div className="hero-content">
          <p className="eyebrow">RDW Open Data</p>
          <h1 className="hero-title-orange">Nederlands kenteken opzoeken</h1>
          <p className="intro">Voer een Nederlands kenteken in. Data afkomstig van RDW Open Data wordt bij de zoekopdracht opgehaald en overzichtelijk getoond.</p>
        </div>
      </section>

      <section className="panel search-panel">
        <form onSubmit={handleSubmit} noValidate>
          <label htmlFor="kenteken">Kenteken</label>
          <div className="search-row">
            <input
              id="kenteken"
              name="kenteken"
              value={kenteken}
              onChange={(event) => setKenteken(event.target.value)}
              placeholder="Bijv. AB-123-C"
              autoComplete="off"
              inputMode="text"
              aria-describedby="kenteken-help"
              className={kenteken && !valid ? 'invalid' : ''}
            />
            <button type="submit" disabled={loading}>{loading ? 'Zoeken…' : 'Zoeken'}</button>
          </div>
          <p id="kenteken-help" className="help">Streepjes en spaties worden automatisch genegeerd. Genormaliseerd: <strong>{normalized || '—'}</strong></p>
        </form>
      </section>

      {error && <div className="error" role="alert">{error}</div>}
      {loading && <div className="loading" role="status">RDW Open Data wordt opgehaald…</div>}
      {result && <Results result={result} />}

      <footer className="footer">
        <p>Deze publieke app toont alleen velden die door RDW Open Data worden teruggegeven. Er worden geen accounts, bestanden of persoonlijke eigenaargegevens beheerd.</p>
      </footer>
    </main>
  );
}
