import React, { useState, useEffect } from 'react';
import { 
  Send, 
  RefreshCw, 
  Trash2, 
  Database, 
  Cpu, 
  Clock, 
  Layers, 
  AlertTriangle,
  CheckCircle,
  FileText,
  Activity,
  ArrowRight
} from 'lucide-react';

const API_BASE_URL = 'http://localhost:3000/api/v1/events';

const EVENT_TEMPLATES = {
  page_view: {
    event_type: 'page_view',
    properties: {
      page_title: 'Pricing & Plans',
      url: '/pricing',
      referrer: 'google_ads',
      device: 'mobile'
    }
  },
  conversion: {
    event_type: 'conversion',
    properties: {
      company_id: '880e8400-e29b-41d4-a716-446655449999',
      conversion_page: 'ebook-rails-streaming-download',
      conversion_value: 250.00,
      job_title: 'Software Architect'
    }
  },
  newsletter_signup: {
    event_type: 'newsletter_signup',
    properties: {
      newsletter_topic: 'distributed_systems',
      consent_given: true,
      signup_source: 'footer_widget'
    }
  },
  add_to_cart: {
    event_type: 'add_to_cart',
    properties: {
      product_id: 'prod_998273',
      product_name: 'Premium Analytics Add-on',
      price: 99.00,
      currency: 'USD'
    }
  }
};

const MOCK_IDENTITIES = [
  { name: 'Ana Silva', email: 'ana.silva@empresa.com.br' },
  { name: 'Bruno Santos', email: 'bruno.santos@techstart.io' },
  { name: 'Camila Oliveira', email: 'camila.oliveira@growthcorp.com' },
  { name: 'Diego Rodrigues', email: 'diego.rodrigues@devs.com.br' },
  { name: 'Elena Costa', email: 'elena.costa@saasmarketing.net' },
  { name: 'Felipe Almeida', email: 'felipe.almeida@fintechhub.co' },
  { name: 'Gabriela Lima', email: 'gabriela.lima@agenciadigital.com' },
  { name: 'Hugo Pereira', email: 'hugo.pereira@analyticslabs.io' }
];

function App() {
  // Simulator State
  const [eventType, setEventType] = useState('page_view');
  const [customEventId, setCustomEventId] = useState('');
  const [customLeadId, setCustomLeadId] = useState('');
  const [customProperties, setCustomProperties] = useState('');
  const [useRandom, setUseRandom] = useState(true);

  // Response Status
  const [isSending, setIsSending] = useState(false);
  const [lastResponse, setLastResponse] = useState(null);
  const [lastLatency, setLastLatency] = useState(null);

  // Pipeline Animation Nodes
  const [pipelineState, setPipelineState] = useState('idle'); // idle, sending, queued, persisted

  // Debug DB inspection states
  const [kafkaQueue, setKafkaQueue] = useState([]);
  const [clickhouseStore, setClickhouseStore] = useState([]);
  const [elasticsearchStore, setElasticsearchStore] = useState([]);
  const [activeInspectorTab, setActiveInspectorTab] = useState('clickhouse');
  const [searchQuery, setSearchQuery] = useState('');
  const [isRefreshing, setIsRefreshing] = useState(false);

  // Analytics Stats
  const [stats, setStats] = useState({
    sentCount: 0,
    successCount: 0,
    failCount: 0,
    avgLatency: 0
  });

  // Expanded log payload IDs
  const [expandedLogId, setExpandedLogId] = useState(null);

  // Toast notifications
  const [toast, setToast] = useState(null);

  // Auto-generate random values
  const generateRandomValues = () => {
    // Generate valid UUID v4
    const uuid = () => 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function(c) {
      const r = Math.random() * 16 | 0;
      const v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });

    setCustomEventId(uuid());
    setCustomLeadId(uuid());
    
    // Format preset properties with randomized contact details
    const randomIdentity = MOCK_IDENTITIES[Math.floor(Math.random() * MOCK_IDENTITIES.length)];
    const presetProps = {
      ...EVENT_TEMPLATES[eventType].properties,
      contact_name: randomIdentity.name,
      contact_email: randomIdentity.email
    };
    setCustomProperties(JSON.stringify(presetProps, null, 2));
  };

  useEffect(() => {
    if (useRandom) {
      generateRandomValues();
    }
  }, [eventType, useRandom]);

  // Fetch debug database states from Rails API
  const fetchDebugData = async (silent = false) => {
    if (!silent) setIsRefreshing(true);
    try {
      const res = await fetch(`${API_BASE_URL}/debug`);
      if (res.ok) {
        const data = await res.json();
        setKafkaQueue(data.kafka_queue || []);
        setClickhouseStore(data.clickhouse_store || []);
        setElasticsearchStore(data.elasticsearch_store || []);
      }
    } catch (err) {
      console.error('Failed to fetch debug state from Rails:', err);
    } finally {
      if (!silent) setIsRefreshing(false);
    }
  };

  // Poll debug data every 3 seconds
  useEffect(() => {
    fetchDebugData(true);
    const interval = setInterval(() => {
      fetchDebugData(true);
    }, 3000);
    return () => clearInterval(interval);
  }, []);

  // Show Toast
  const showToast = (type, message) => {
    setToast({ type, message });
    setTimeout(() => {
      setToast(null);
    }, 4000);
  };

  // Clear mock databases
  const handleClearDatabases = async () => {
    try {
      const res = await fetch(`${API_BASE_URL}/clear`, { method: 'POST' });
      if (res.ok) {
        showToast('success', 'Simulator data cleared successfully.');
        fetchDebugData();
        setStats({ sentCount: 0, successCount: 0, failCount: 0, avgLatency: 0 });
        setLastResponse(null);
        setLastLatency(null);
      }
    } catch (err) {
      showToast('error', 'Failed to clear database state.');
    }
  };

  // Send Event simulation
  const handleSendEvent = async (e) => {
    e.preventDefault();
    setIsSending(true);
    setPipelineState('sending');
    const startTime = performance.now();

    let propertiesObj = {};
    try {
      propertiesObj = JSON.parse(customProperties);
    } catch (err) {
      showToast('error', 'Lead Properties field contains invalid JSON.');
      setIsSending(false);
      setPipelineState('idle');
      return;
    }

    const payload = {
      event_id: customEventId,
      lead_id: customLeadId,
      event_type: eventType,
      timestamp: new Date().toISOString(),
      properties: propertiesObj
    };

    try {
      const response = await fetch(API_BASE_URL, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(payload)
      });

      const latency = Math.round(performance.now() - startTime);
      setLastLatency(latency);
      const resData = await response.json();
      setLastResponse({ status: response.status, data: resData });

      if (response.status === 202) {
        // Stream completed successfully to API and queued to Kafka
        setPipelineState('queued');
        showToast('success', 'Event captured! Forwarded to Message Queue (Redpanda).');
        
        // Update stats
        setStats(prev => {
          const newCount = prev.successCount + 1;
          const newTotal = prev.sentCount + 1;
          const newAvg = Math.round(((prev.avgLatency * prev.sentCount) + latency) / newTotal);
          return {
            ...prev,
            sentCount: newTotal,
            successCount: newCount,
            avgLatency: newAvg
          };
        });

        // Trigger simulation pipeline steps
        setTimeout(() => {
          setPipelineState('persisted');
          fetchDebugData(true);
        }, 1200);

      } else {
        // Validation/422/500 errors
        setPipelineState('idle');
        showToast('error', resData.errors ? 'Validation failed! Check contact properties.' : 'API connection issue.');
        setStats(prev => ({
          ...prev,
          sentCount: prev.sentCount + 1,
          failCount: prev.failCount + 1
        }));
      }

    } catch (err) {
      setPipelineState('idle');
      showToast('error', 'Network failure connecting to Marketing Hub. Is Rails server running?');
      setStats(prev => ({
        ...prev,
        sentCount: prev.sentCount + 1,
        failCount: prev.failCount + 1
      }));
    } finally {
      setIsSending(false);
      // Regen UUIDs if using randomizer
      if (useRandom) {
        // slight delay to let user see sent UUID
        setTimeout(() => {
          generateRandomValues();
        }, 800);
      }
    }
  };

  // Filter Elasticsearch lead index based on search query
  const filteredElasticsearch = elasticsearchStore.filter(item => {
    if (!searchQuery) return true;
    const query = searchQuery.toLowerCase();
    return (
      item.event_id?.toLowerCase().includes(query) ||
      item.lead_id?.toLowerCase().includes(query) ||
      item.event_type?.toLowerCase().includes(query) ||
      JSON.stringify(item.properties || {}).toLowerCase().includes(query)
    );
  });

  return (
    <div className="app-container">
      {/* Toast Notification */}
      {toast && (
        <div className={`toast toast-${toast.type}`}>
          {toast.type === 'success' ? (
            <CheckCircle size={18} className="color-success" />
          ) : (
            <AlertTriangle size={18} className="color-primary" />
          )}
          <span>{toast.message}</span>
        </div>
      )}

      {/* Header */}
      <header className="header">
        <div className="header-title-section">
          <Activity size={32} style={{ color: 'var(--color-primary)' }} />
          <div>
            <h1>Lead Tracking & Marketing Automation Hub</h1>
            <p style={{ margin: 0, fontSize: '0.85rem', color: 'var(--text-muted)' }}>
              RD Station & HubSpot Data Pipeline Simulator (Rails API Backend)
            </p>
          </div>
        </div>
        <div className="badge-connected">
          <div className="pulse-dot"></div>
          <span>API Connection: Active</span>
        </div>
      </header>

      {/* Stats Summary Panel */}
      <div className="latency-stats-row">
        <div className="stat-box">
          <div className="stat-label">Tracked Contact Actions (Rails API)</div>
          <div className="stat-value color-info">{stats.sentCount}</div>
        </div>
        <div className="stat-box">
          <div className="stat-label">Stored Contacts & Leads (ClickHouse & ES)</div>
          <div className="stat-value color-success">{stats.successCount}</div>
        </div>
        <div className="stat-box">
          <div className="stat-label">Processing Speed (API Latency)</div>
          <div className="stat-value color-primary">{stats.avgLatency} ms</div>
        </div>
      </div>

      {/* Pipeline Flow Simulation Visualizer */}
      <section className="card" style={{ marginBottom: '2rem' }}>
        <div className="card-title-bar">
          <h2>
            <Layers size={18} className="color-primary" />
            Real-time Event Delivery Pipeline (Redpanda / ClickHouse / Elasticsearch)
          </h2>
          <span style={{ fontSize: '0.8rem', color: 'var(--text-muted)' }}>
            Pipeline Status: <strong style={{ color: 'var(--text-highlight)' }}>{pipelineState === 'persisted' ? 'SYNCHRONIZED' : pipelineState.toUpperCase()}</strong>
          </span>
        </div>
        <div className="pipeline-visualizer">
          <div className={`pipeline-node ${['sending', 'queued', 'persisted'].includes(pipelineState) ? 'active' : ''} ${['queued', 'persisted'].includes(pipelineState) ? 'processed' : ''}`}>
            <div className="pipeline-icon">
              <Cpu size={24} />
            </div>
            <div className="pipeline-label">Website Form / API (Rails)</div>
          </div>

          <div className={`pipeline-connector ${['sending'].includes(pipelineState) ? 'active' : ''} ${['queued', 'persisted'].includes(pipelineState) ? 'processed' : ''}`}></div>

          <div className={`pipeline-node ${['queued', 'persisted'].includes(pipelineState) ? 'active' : ''} ${['persisted'].includes(pipelineState) ? 'processed' : ''}`}>
            <div className="pipeline-icon">
              <Activity size={24} />
            </div>
            <div className="pipeline-label">Message Delivery Queue (Redpanda)</div>
          </div>

          <div className={`pipeline-connector ${['queued'].includes(pipelineState) ? 'active' : ''} ${['persisted'].includes(pipelineState) ? 'processed' : ''}`}></div>

          <div className={`pipeline-node ${['persisted'].includes(pipelineState) ? 'active' : ''} ${['persisted'].includes(pipelineState) ? 'processed' : ''}`}>
            <div className="pipeline-icon">
              <Database size={24} />
            </div>
            <div className="pipeline-label">Marketing Analytics Store (ClickHouse)</div>
          </div>

          <div className={`pipeline-connector ${['queued'].includes(pipelineState) ? 'active' : ''} ${['persisted'].includes(pipelineState) ? 'processed' : ''}`}></div>

          <div className={`pipeline-node ${['persisted'].includes(pipelineState) ? 'active' : ''} ${['persisted'].includes(pipelineState) ? 'processed' : ''}`}>
            <div className="pipeline-icon">
              <Layers size={24} />
            </div>
            <div className="pipeline-label">Contacts Search & Segmentation Index (Elasticsearch)</div>
          </div>
        </div>
      </section>

      {/* Main Grid */}
      <div className="dashboard-grid">
        {/* Left Column: Form Simulator */}
        <section className="card">
          <div className="card-title-bar">
            <h2>
              <Send size={18} style={{ color: 'var(--color-primary)' }} />
              HubSpot-style Lead Action Simulator
            </h2>
            <button 
              className="btn btn-secondary" 
              style={{ padding: '0.25rem 0.5rem', fontSize: '0.75rem' }}
              onClick={generateRandomValues}
              type="button"
            >
              Regen IDs
            </button>
          </div>

          <form onSubmit={handleSendEvent}>
            <div className="form-group">
              <label>Select Contact Trigger Action</label>
              <select 
                value={eventType} 
                onChange={(e) => setEventType(e.target.value)}
              >
                <option value="page_view">Page View (e.g. /pricing)</option>
                <option value="conversion">Form Conversion (e.g. Ebook download)</option>
                <option value="newsletter_signup">Newsletter Subscription</option>
                <option value="add_to_cart">E-commerce Checkout Action</option>
              </select>
            </div>

            <div className="form-group">
              <label>Event Ingestion Token (Rails Event UUID)</label>
              <input 
                type="text" 
                className="form-control mono-input"
                value={customEventId}
                onChange={(e) => {
                  setCustomEventId(e.target.value);
                  setUseRandom(false);
                }}
                required 
              />
            </div>

            <div className="form-group">
              <label>Contact Reference Token (Rails Lead UUID)</label>
              <input 
                type="text" 
                className="form-control mono-input"
                value={customLeadId}
                onChange={(e) => {
                  setCustomLeadId(e.target.value);
                  setUseRandom(false);
                }}
                required 
              />
            </div>

            <div className="form-group">
              <label>Lead Custom Properties (JSON Metadata)</label>
              <textarea 
                className="form-control mono-input"
                rows={5}
                value={customProperties}
                onChange={(e) => {
                  setCustomProperties(e.target.value);
                  setUseRandom(false);
                }}
                required
              />
            </div>

            <div className="form-group" style={{ display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
              <input 
                type="checkbox" 
                id="useRandom" 
                checked={useRandom} 
                onChange={(e) => setUseRandom(e.target.checked)} 
              />
              <label htmlFor="useRandom" style={{ margin: 0, cursor: 'pointer', fontSize: '0.85rem' }}>
                Auto-generate unique contact identity
              </label>
            </div>

            <button 
              type="submit" 
              className="btn btn-primary btn-full"
              disabled={isSending}
            >
              {isSending ? (
                <>
                  <RefreshCw size={18} className="animate-spin" />
                  Streaming Action...
                </>
              ) : (
                <>
                  <Send size={18} />
                  Simulate Customer Action (POST /api/v1/events)
                </>
              )}
            </button>
          </form>

          {/* Last Response Inspector */}
          {lastResponse && (
            <div style={{ marginTop: '1.5rem', borderTop: '1px solid var(--border-color)', paddingTop: '1.25rem' }}>
              <h3 style={{ fontSize: '0.9rem', marginBottom: '0.75rem', display: 'flex', alignItems: 'center', gap: '0.5rem' }}>
                <FileText size={16} />
                HubSpot Event Ingestion Status (Rails API Response)
              </h3>
              <div 
                className="event-payload-collapse" 
                style={{ 
                  backgroundColor: lastResponse.status === 202 ? 'rgba(16, 185, 129, 0.05)' : 'rgba(239, 68, 68, 0.05)',
                  borderColor: lastResponse.status === 202 ? 'rgba(16, 185, 129, 0.2)' : 'rgba(239, 68, 68, 0.2)',
                  color: lastResponse.status === 202 ? '#34d399' : '#f87171'
                }}
              >
                <pre style={{ margin: 0, whiteSpace: 'pre-wrap' }}>
                  {JSON.stringify(lastResponse.data, null, 2)}
                </pre>
              </div>
            </div>
          )}
        </section>

        {/* Right Column: Database Inspector */}
        <section className="card">
          <div className="card-title-bar">
            <h2>
              <Database size={18} className="color-info" />
              Real-time Data Pipeline Monitor (Mock DB Inspector)
            </h2>
            <div className="btn-group">
              <button 
                className="btn btn-secondary" 
                style={{ padding: '0.35rem 0.75rem', fontSize: '0.8rem' }}
                onClick={() => fetchDebugData()}
                disabled={isRefreshing}
              >
                <RefreshCw size={14} className={isRefreshing ? 'animate-spin' : ''} />
                Refresh
              </button>
              <button 
                className="btn btn-danger" 
                style={{ padding: '0.35rem 0.75rem', fontSize: '0.8rem' }}
                onClick={handleClearDatabases}
              >
                <Trash2 size={14} />
                Reset All Data
              </button>
            </div>
          </div>

          <div className="tabs-header">
            <button 
              className={`tab-btn ${activeInspectorTab === 'clickhouse' ? 'active' : ''}`}
              onClick={() => setActiveInspectorTab('clickhouse')}
            >
              Analytics & Performance DB (ClickHouse) ({clickhouseStore.length})
            </button>
            <button 
              className={`tab-btn ${activeInspectorTab === 'elasticsearch' ? 'active' : ''}`}
              onClick={() => setActiveInspectorTab('elasticsearch')}
            >
              Lead Segmentation DB (Elasticsearch) ({elasticsearchStore.length})
            </button>
            <button 
              className={`tab-btn ${activeInspectorTab === 'kafka' ? 'active' : ''}`}
              onClick={() => setActiveInspectorTab('kafka')}
            >
              Kafka Stream Buffer (Redpanda) ({kafkaQueue.length})
            </button>
          </div>

          <div className="db-inspector-container">
            {/* ClickHouse Table Content */}
            {activeInspectorTab === 'clickhouse' && (
              <div className="db-grid">
                {clickhouseStore.length === 0 ? (
                  <div className="no-data-placeholder">
                    No customer actions recorded in ClickHouse yet. Trigger events in the simulator to populate reporting.
                  </div>
                ) : (
                  <div className="db-table-wrapper">
                    <table>
                      <thead>
                        <tr>
                          <th>Event Ref</th>
                          <th>Contact Profile</th>
                          <th>Action Type</th>
                          <th>Time Logged</th>
                        </tr>
                      </thead>
                      <tbody>
                        {clickhouseStore.map((item, idx) => (
                          <tr key={idx} onClick={() => setExpandedLogId(expandedLogId === item.event_id ? null : item.event_id)} style={{ cursor: 'pointer' }}>
                            <td className="mono-input" style={{ color: 'var(--color-primary)' }}>{item.event_id?.slice(0, 8)}...</td>
                            <td>
                              <div style={{ fontWeight: '500', color: 'var(--text-highlight)' }}>{item.properties?.contact_name || 'Anonymous Lead'}</div>
                              <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>{item.properties?.contact_email || `ID: ${item.lead_id?.slice(0, 8)}...`}</div>
                            </td>
                            <td>
                              <span className={`badge badge-${item.event_type}`}>
                                {item.event_type}
                              </span>
                            </td>
                            <td className="event-time">{item.timestamp ? new Date(item.timestamp).toLocaleTimeString() : 'N/A'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}

            {/* Elasticsearch Content */}
            {activeInspectorTab === 'elasticsearch' && (
              <div className="db-grid">
                <div style={{ marginBottom: '1rem' }}>
                  <input
                    type="text"
                    placeholder="Search leads in Elasticsearch (by Contact ID, Action Type, or Custom Properties)..."
                    className="form-control"
                    value={searchQuery}
                    onChange={(e) => setSearchQuery(e.target.value)}
                    style={{ fontSize: '0.85rem' }}
                  />
                </div>
                {filteredElasticsearch.length === 0 ? (
                  <div className="no-data-placeholder">
                    {elasticsearchStore.length === 0 
                      ? "No contacts indexed in Elasticsearch yet." 
                      : "No matching leads found for your search."}
                  </div>
                ) : (
                  <div className="db-table-wrapper">
                    <table>
                      <thead>
                        <tr>
                          <th>Index Doc ID</th>
                          <th>Contact Profile</th>
                          <th>Action Type</th>
                          <th>Index Timestamp</th>
                        </tr>
                      </thead>
                      <tbody>
                        {filteredElasticsearch.map((item, idx) => (
                          <tr key={idx} onClick={() => setExpandedLogId(expandedLogId === item.event_id ? null : item.event_id)} style={{ cursor: 'pointer' }}>
                            <td className="mono-input" style={{ color: 'var(--color-info)' }}>es_{item.event_id?.slice(0, 6)}</td>
                            <td>
                              <div style={{ fontWeight: '500', color: 'var(--text-highlight)' }}>{item.properties?.contact_name || 'Anonymous Lead'}</div>
                              <div style={{ fontSize: '0.75rem', color: 'var(--text-muted)' }}>{item.properties?.contact_email || `ID: ${item.lead_id?.slice(0, 8)}...`}</div>
                            </td>
                            <td>
                              <span className={`badge badge-${item.event_type}`}>
                                {item.event_type}
                              </span>
                            </td>
                            <td className="event-time">{item.timestamp ? new Date(item.timestamp).toLocaleTimeString() : 'N/A'}</td>
                          </tr>
                        ))}
                      </tbody>
                    </table>
                  </div>
                )}
              </div>
            )}

            {/* Kafka/Redpanda Content */}
            {activeInspectorTab === 'kafka' && (
              <div className="db-grid">
                {kafkaQueue.length === 0 ? (
                  <div className="no-data-placeholder">
                    Redpanda queue is empty (All streamed events consumed and synchronized).
                  </div>
                ) : (
                  <div className="event-log-list">
                    {kafkaQueue.map((item, idx) => (
                      <div 
                        key={idx} 
                        className="event-log-item"
                        onClick={() => setExpandedLogId(expandedLogId === item.event_id ? null : item.event_id)}
                      >
                        <div className="event-log-header">
                          <div className="event-log-meta">
                            <span className={`badge badge-${item.event_type}`}>{item.event_type}</span>
                            <span className="mono-input" style={{ fontSize: '0.75rem' }}>{item.event_id}</span>
                          </div>
                          <span className="event-time">{new Date(item.timestamp).toLocaleTimeString()}</span>
                        </div>
                        {expandedLogId === item.event_id && (
                          <div className="event-payload-collapse" onClick={(e) => e.stopPropagation()}>
                            <pre style={{ margin: 0 }}>
                              {JSON.stringify(item, null, 2)}
                            </pre>
                          </div>
                        )}
                      </div>
                    ))}
                  </div>
                )}
              </div>
            )}

            {/* Expanded Item Payload View */}
            {expandedLogId && (
              <div style={{ marginTop: '1rem', borderTop: '1px solid var(--border-color)', paddingTop: '1rem' }}>
                <h3 style={{ fontSize: '0.9rem', marginBottom: '0.5rem' }}>Full Object Properties ({expandedLogId.slice(0, 8)})</h3>
                <div className="event-payload-collapse">
                  <pre style={{ margin: 0 }}>
                    {JSON.stringify(
                      [...clickhouseStore, ...elasticsearchStore, ...kafkaQueue].find(x => x.event_id === expandedLogId) || {}, 
                      null, 
                      2
                    )}
                  </pre>
                </div>
              </div>
            )}
          </div>
        </section>
      </div>
    </div>
  );
}

export default App;
