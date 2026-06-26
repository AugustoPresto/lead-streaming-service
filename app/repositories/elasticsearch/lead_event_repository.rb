# frozen_string_literal: true

module Elasticsearch
  class LeadEventRepository
    INDEX_NAME = "lead_events"

    class << self
      def mock_store
        @mock_store ||= []
      end

      def clear_mock_store!
        @mock_store = []
      end

      # Performs bulk indexing of events
      # @param events [Array<Hash>] list of events to index
      def bulk_index(events)
        return true if events.empty?

        if mock_enabled?
          Rails.logger.info("[Elasticsearch::LeadEventRepository][MOCK] Bulk indexing #{events.size} events into #{INDEX_NAME}")
          mock_store.concat(events)
          return true
        end

        body = events.flat_map do |event|
          [
            { index: { _index: INDEX_NAME, _id: event[:event_id] } },
            event
          ]
        end

        response = client.bulk(body: body)
        
        if response["errors"]
          Rails.logger.error("[Elasticsearch::LeadEventRepository] Bulk indexing completed with errors: #{response}")
          # Depending on SLA, we can retry, send to DLQ, or raise
          raise "Elasticsearch bulk indexing failed"
        end

        true
      rescue => e
        Rails.logger.error("[Elasticsearch::LeadEventRepository] Elasticsearch connection failed: #{e.message}")
        Sentry.capture_exception(e)
        raise e
      end

      private

      def mock_enabled?
        ENV.fetch("MOCK_ELASTICSEARCH", "true") == "true"
      end

      def client
        @client ||= ::Elasticsearch::Client.new(
          url: ENV.fetch("ELASTICSEARCH_URL", "http://localhost:9200"),
          retry_on_failure: 3,
          request_timeout: 5
        )
      end
    end
  end
end
