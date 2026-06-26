# frozen_string_literal: true

module LeadEvents
  class Producer
    TOPIC = "lead-events"

    class << self
      # In-memory queue for testing and mock mode
      def mock_queue
        @mock_queue ||= []
      end

      def clear_mock_queue!
        @mock_queue = []
      end

      # Publishes an event to the queue
      # @param event_params [Hash] the validated event payload
      def publish(event_params)
        payload = event_params.to_json

        if mock_enabled?
          Rails.logger.info("[LeadEvents::Producer][MOCK] Publishing event to topic '#{TOPIC}': #{payload}")
          mock_queue << event_params
          true
        else
          # Production implementation using rdkafka/karafka
          producer.produce(
            topic: TOPIC,
            payload: payload,
            key: event_params[:lead_id] # Keying by lead_id ensures in-order delivery of lead actions
          )
          true
        end
      rescue => e
        # High Availability: log and raise for error handler / circuit breaker
        Rails.logger.error("[LeadEvents::Producer] Failed to publish event: #{e.message}")
        Sentry.capture_exception(e)
        raise e
      end

      private

      def mock_enabled?
        ENV.fetch("MOCK_KAFKA", "true") == "true"
      end

      # Thread-safe lazy initialization of the real Kafka producer
      def producer
        @producer ||= begin
          config = {
            "bootstrap.servers": ENV.fetch("KAFKA_BROKERS", "localhost:9092"),
            "client.id": "rd-marketing-producer"
          }
          # Assuming rdkafka gem is configured. We lazily load it.
          require "rdkafka"
          Rdkafka::Config.new(config).producer
        end
      end
    end
  end
end
