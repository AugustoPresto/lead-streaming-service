# frozen_string_literal: true

module Api
  module V1
    class EventsController < ApplicationController
      # POST /api/v1/events
      def create
        # Use dry-validation contract to validate payload structure
        contract = EventIngestionContract.new
        validation_result = contract.call(event_params.to_h)

        if validation_result.success?
          # Stream event to Kafka
          LeadEvents::Producer.publish(validation_result.to_h)

          # Track metrics: increment request count (Prometheus metric via Yabeda)
          Yabeda.rd_marketing.events_ingested.increment({ event_type: validation_result[:event_type] })

          render json: {
            event_id: validation_result[:event_id],
            status: "accepted",
            message: "Event successfully queued for ingestion."
          }, status: :accepted
        else
          # Track metrics: increment validation failures
          Yabeda.rd_marketing.validation_failures.increment({ reason: "invalid_schema" })

          render json: {
            errors: validation_result.errors.to_h
          }, status: :unprocessable_entity
        end
      rescue => e
        # Track metrics: increment server errors
        Yabeda.rd_marketing.server_errors.increment({ controller: "events", action: "create" })
        
        Rails.logger.error("[Api::V1::EventsController] Failed to ingest event: #{e.message}")
        Sentry.capture_exception(e)

        render json: {
          error: "Internal server error. The ingestion service is temporarily unavailable."
        }, status: :internal_server_error
      end

      # GET /api/v1/events/debug
      def debug
        # In mock mode, process queued events synchronously to simulate background worker consumption
        # since Puma and Rake daemons run in separate OS memory spaces.
        if LeadEvents::Producer.mock_queue.any?
          messages = LeadEvents::Producer.mock_queue.map do |event|
            Struct.new(:payload).new(event.to_json)
          end

          begin
            LeadEvents::Consumer.process_batch(messages)
            LeadEvents::Producer.clear_mock_queue!
          rescue => e
            Rails.logger.error("[Api::V1::EventsController] Mock processing failed: #{e.message}")
          end
        end

        render json: {
          kafka_queue: LeadEvents::Producer.mock_queue,
          clickhouse_store: Clickhouse::LeadEventRepository.mock_store,
          elasticsearch_store: Elasticsearch::LeadEventRepository.mock_store
        }
      end

      # POST /api/v1/events/clear
      def clear
        LeadEvents::Producer.clear_mock_queue!
        Clickhouse::LeadEventRepository.clear_mock_store!
        Elasticsearch::LeadEventRepository.clear_mock_store!
        render json: { status: "success", message: "Mock databases cleared." }
      end

      private

      def event_params
        # Permit arbitrary fields inside properties
        params.permit(:event_id, :lead_id, :event_type, :timestamp, properties: {})
      end
    end
  end
end
