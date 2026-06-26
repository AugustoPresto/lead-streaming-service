CREATE DATABASE IF NOT EXISTS rd_analytics;

-- Lead Events table using ReplacingMergeTree for event deduplication
CREATE TABLE IF NOT EXISTS rd_analytics.lead_events (
    event_id UUID,
    lead_id UUID,
    company_id Nullable(UUID),
    event_type LowCardinality(String),
    payload String,
    created_at DateTime64(3, 'UTC'),
    processed_at DateTime64(3, 'UTC')
) ENGINE = ReplacingMergeTree(processed_at)
PARTITION BY toYYYYMM(created_at)
PRIMARY KEY (event_id)
ORDER BY (event_id, lead_id, event_type, created_at)
SETTINGS index_granularity = 8192;
