# frozen_string_literal: true

module Elasticsearch
  class LeadEventRepository
    INDEX_NAME = "lead_events"

    class << self
      def mock_store
        @mock_store ||= load_mock_store
      end

      def load_mock_store
        path = Rails.root.join("db", "mock_elasticsearch.json")
        if File.exist?(path)
          begin
            JSON.parse(File.read(path), symbolize_names: true)
          rescue => e
            Rails.logger.error("[Elasticsearch::LeadEventRepository] Failed to read mock file: #{e.message}")
            []
          end
        else
          []
        end
      end

      def save_mock_store!
        path = Rails.root.join("db", "mock_elasticsearch.json")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(mock_store))
      rescue => e
        Rails.logger.error("[Elasticsearch::LeadEventRepository] Failed to write mock file: #{e.message}")
      end

      def clear_mock_store!
        @mock_store = []
        save_mock_store!
      end

      # Performs bulk indexing of events
      # @param events [Array<Hash>] list of events to index
      def bulk_index(events)
        return true if events.empty?

        if mock_enabled?
          Rails.logger.info("[Elasticsearch::LeadEventRepository][MOCK] Bulk indexing #{events.size} events into #{INDEX_NAME}")
          mock_store.concat(events)
          save_mock_store!
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
