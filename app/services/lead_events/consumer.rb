# frozen_string_literal: true

module LeadEvents
  class Consumer
    BATCH_SIZE = 1000
    BATCH_TIMEOUT = 2.0 # seconds

    class << self
      # Processes a batch of raw Kafka messages
      # @param messages [Array<Object>] list of Kafka messages containing keys and payloads
      def process_batch(messages)
        return if messages.empty?

        Rails.logger.info("[LeadEvents::Consumer] Processing batch of #{messages.size} events...")

        # Parse messages
        events = messages.map do |msg|
          begin
            payload = JSON.parse(msg.payload, symbolize_names: true)
            # Ensure it matches the expected structure
            {
              event_id: payload[:event_id],
              lead_id: payload[:lead_id],
              event_type: payload[:event_type],
              timestamp: payload[:timestamp],
              properties: payload[:properties] || {},
              processed_at: Time.now.utc.iso8601(3)
            }
          rescue JSON::ParserError => e
            Rails.logger.error("[LeadEvents::Consumer] Failed to parse message payload: #{e.message}")
            Sentry.capture_exception(e)
            nil
          end
        end.compact

        return if events.empty?

        # High-throughput batch writes
        # By executing writes in parallel (or sequential but in transaction-like batch calls),
        # we minimize connection overhead. ClickHouse excels at large batch insertions.
        
        # 1. Bulk insert to Clickhouse
        clickhouse_success = write_to_clickhouse(events)

        # 2. Bulk index to Elasticsearch
        elasticsearch_success = write_to_elasticsearch(events)

        if clickhouse_success && elasticsearch_success
          Rails.logger.info("[LeadEvents::Consumer] Batch of #{events.size} events successfully processed.")
          true
        else
          # If either database fails, we raise an error. Kafka will retry this partition,
          # ensuring consistency. In production, we'd also utilize a Dead Letter Queue (DLQ)
          # for poison pill events, but raising here ensures we don't drop data.
          raise "Batch processing failed: Clickhouse: #{clickhouse_success}, Elasticsearch: #{elasticsearch_success}"
        end
      end

      # Starts the consumer polling loop (usually invoked by rake task / K8s pod)
      def start
        Rails.logger.info("[LeadEvents::Consumer] Starting Kafka Lead Events Consumer...")
        
        if mock_enabled?
          Rails.logger.info("[LeadEvents::Consumer][MOCK] Running in Mock Consumer mode.")
          run_mock_loop
        else
          run_kafka_loop
        end
      end

      private

      def mock_enabled?
        ENV.fetch("MOCK_KAFKA", "true") == "true"
      end

      def write_to_clickhouse(events)
        Clickhouse::LeadEventRepository.bulk_insert(events)
        true
      rescue => e
        Rails.logger.error("[LeadEvents::Consumer] Clickhouse bulk write failed: #{e.message}")
        false
      end

      def write_to_elasticsearch(events)
        Elasticsearch::LeadEventRepository.bulk_index(events)
        true
      rescue => e
        Rails.logger.error("[LeadEvents::Consumer] Elasticsearch bulk index failed: #{e.message}")
        false
      end

      # A mock loop that periodically checks the Producer's mock queue to simulate streaming
      def run_mock_loop
        @running = true
        while @running
          mock_messages = Producer.mock_queue.shift(BATCH_SIZE)
          unless mock_messages.empty?
            # Wrap in structure resembling Kafka messages
            wrapped_messages = mock_messages.map do |evt|
              Struct.new(:payload).new(evt.to_json)
            end
            process_batch(wrapped_messages)
          end
          sleep BATCH_TIMEOUT
        end
      end

      # Real Kafka polling using Karafka or rdkafka
      def run_kafka_loop
        require "rdkafka"
        
        config = {
          "bootstrap.servers": ENV.fetch("KAFKA_BROKERS", "localhost:9092"),
          "group.id": "rd-marketing-consumer-group",
          "enable.auto.commit": "false" # Manually commit offsets after successful processing
        }
        
        consumer = Rdkafka::Config.new(config).consumer
        consumer.subscribe(Producer::TOPIC)

        batch = []
        last_flush = Time.now

        @running = true
        while @running
          # Poll with short timeout
          message = consumer.poll(100) # ms
          
          if message
            batch << message
          end

          # Flush if batch size is reached or timeout elapsed
          if batch.any? && (batch.size >= BATCH_SIZE || (Time.now - last_flush) >= BATCH_TIMEOUT)
            process_batch(batch)
            consumer.commit # Commit Kafka offset
            batch.clear
            last_flush = Time.now
          end
        end
      rescue => e
        Rails.logger.fatal("[LeadEvents::Consumer] Consumer loop crashed: #{e.message}")
        Sentry.capture_exception(e)
        raise e
      ensure
        consumer&.close
      end
    end
  end
end
