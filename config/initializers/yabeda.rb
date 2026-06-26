# frozen_string_literal: true

Yabeda.configure do
  group :rd_marketing do
    # Counter for total ingested lead events
    counter :events_ingested do
      comment "Total number of successfully ingested and queued lead events"
      tags [:event_type]
    end

    # Counter for schema validation failures
    counter :validation_failures do
      comment "Total number of events that failed schema validation"
      tags [:reason]
    end

    # Counter for internal server/connection errors
    counter :server_errors do
      comment "Total number of internal server errors during event ingestion"
      tags [:controller, :action]
    end

    # Histogram for tracking Clickhouse bulk write latency
    histogram :clickhouse_bulk_insert_latency do
      comment "Latency of bulk inserting events into Clickhouse (in seconds)"
      buckets [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
    end

    # Histogram for tracking Elasticsearch bulk index latency
    histogram :elasticsearch_bulk_index_latency do
      comment "Latency of bulk indexing events into Elasticsearch (in seconds)"
      buckets [0.005, 0.01, 0.025, 0.05, 0.1, 0.25, 0.5, 1.0, 2.5, 5.0]
    end
  end
end
