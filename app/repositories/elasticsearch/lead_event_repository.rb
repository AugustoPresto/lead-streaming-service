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

      # Performs search query using Elasticsearch Query DSL
      # @param query [String] search term
      # @return [Array<Hash>] search results
      def search(query)
        return mock_search(query) if mock_enabled?

        return mock_store if query.blank?

        q = {
          query: {
            bool: {
              should: [
                { term: { event_type: query } },
                { term: { lead_id: query } },
                { term: { event_id: query } },
                { multi_match: {
                    query: query,
                    fields: ["properties.contact_name^3", "properties.contact_email^3", "properties.company_name^2", "properties.path"],
                    fuzziness: "AUTO"
                  }
                }
              ]
            }
          }
        }

        response = client.search(index: INDEX_NAME, body: q)
        response["hits"]["hits"].map { |h| h["_source"].with_indifferent_access }
      rescue => e
        Rails.logger.error("[Elasticsearch::LeadEventRepository] Elasticsearch search failed: #{e.message}")
        []
      end

      private

      def mock_search(query)
        return mock_store if query.blank?

        q = query.downcase.strip
        mock_store.select do |event|
          # Match exact fields
          next true if event[:event_id]&.downcase == q || event[:lead_id]&.downcase == q || event[:event_type]&.downcase == q

          # Match properties fields
          properties = event[:properties] || {}
          name = properties[:contact_name]&.downcase || ""
          email = properties[:contact_email]&.downcase || ""
          company = properties[:company_name]&.downcase || ""
          path = properties[:path]&.downcase || ""

          # Simple Levenshtein distance simulation for typo-tolerant fuzzy matching (distance <= 2)
          fuzzy_match = levenshtein_distance(name, q) <= 2 || levenshtein_distance(company, q) <= 2

          name.include?(q) || email.include?(q) || company.include?(q) || path.include?(q) || fuzzy_match
        end
      end

      def levenshtein_distance(s, t)
        m = s.length
        n = t.length
        return m if n == 0
        return n if m == 0
        d = Array.new(m + 1) { Array.new(n + 1) }

        for i in 0..m; d[i][0] = i; end
        for j in 0..n; d[0][j] = j; end

        for j in 1..n
          for i in 1..m
            if s[i - 1] == t[j - 1]
              d[i][j] = d[i - 1][j - 1]
            else
              d[i][j] = [d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + 1].min
            end
          end
        end
        d[m][n]
      end

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
