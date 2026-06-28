# frozen_string_literal: true

module Clickhouse
  class LeadEventRepository
    TABLE_NAME = "rd_analytics.lead_events"

    class << self
      def mock_store
        @mock_store ||= load_mock_store
      end

      def load_mock_store
        path = Rails.root.join("db", "mock_clickhouse.json")
        if File.exist?(path)
          begin
            JSON.parse(File.read(path), symbolize_names: true)
          rescue => e
            Rails.logger.error("[Clickhouse::LeadEventRepository] Failed to read mock file: #{e.message}")
            []
          end
        else
          []
        end
      end

      def save_mock_store!
        path = Rails.root.join("db", "mock_clickhouse.json")
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, JSON.pretty_generate(mock_store))
      rescue => e
        Rails.logger.error("[Clickhouse::LeadEventRepository] Failed to write mock file: #{e.message}")
      end

      def clear_mock_store!
        @mock_store = []
        save_mock_store!
      end

      # Performs bulk insertion of event records into ClickHouse
      # @param events [Array<Hash>] list of events to insert
      def bulk_insert(events)
        return true if events.empty?

        if mock_enabled?
          Rails.logger.info("[Clickhouse::LeadEventRepository][MOCK] Bulk inserting #{events.size} events into #{TABLE_NAME}")
          mock_store.concat(events)
          save_mock_store!
          return true
        end

        columns = %w[event_id lead_id company_id event_type payload created_at processed_at]
        
        # Format events to match column values
        values = events.map do |event|
          properties = event[:properties] || {}
          company_id = properties[:company_id] || properties["company_id"]
          
          [
            event[:event_id],
            event[:lead_id],
            company_id,
            event[:event_type],
            properties.to_json,
            event[:timestamp], # created_at
            Time.now.utc.strftime("%Y-%m-%d %H:%M:%S.%3N") # processed_at
          ]
        end

        # Execute insertion using the clickhouse-ruby client
        connection.insert(TABLE_NAME, columns: columns, values: values)
        true
      rescue => e
        Rails.logger.error("[Clickhouse::LeadEventRepository] Clickhouse insertion failed: #{e.message}")
        Sentry.capture_exception(e)
        raise e
      end

      private

      def mock_enabled?
        ENV.fetch("MOCK_CLICKHOUSE", "true") == "true"
      end

      def connection
        @connection ||= begin
          require "clickhouse"
          Clickhouse.establish_connection(
            host: ENV.fetch("CLICKHOUSE_HOST", "localhost"),
            port: ENV.fetch("CLICKHOUSE_PORT", "8123"),
            database: ENV.fetch("CLICKHOUSE_DATABASE", "rd_analytics"),
            username: ENV.fetch("CLICKHOUSE_USERNAME", "default"),
            password: ENV.fetch("CLICKHOUSE_PASSWORD", "")
          )
          Clickhouse.connection
        end
      end
    end
  end
end
