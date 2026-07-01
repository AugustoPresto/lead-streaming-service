# frozen_string_literal: true

require "rails_helper"

RSpec.describe Api::V1::EventsController, type: :controller do
  let(:valid_payload) do
    {
      event_id: "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
      lead_id: "550e8400-e29b-41d4-a716-446655440000",
      event_type: "page_view",
      timestamp: "2026-06-26T12:00:00Z",
      properties: {
        page_title: "Pricing Page",
        referrer: "google"
      }
    }
  end

  let(:invalid_payload) do
    {
      event_id: "invalid-uuid",
      lead_id: "550e8400-e29b-41d4-a716-446655440000",
      event_type: "",
      timestamp: "2026-06-26T12:00:00Z"
    }
  end

  before do
    # Clear the mock queues/stores before each test
    LeadEvents::Producer.clear_mock_queue!
  end

  describe "POST #create" do
    context "with valid parameters" do
      it "returns http accepted" do
        post :create, params: valid_payload, as: :json
        expect(response).to have_http_status(:accepted)
      end

      it "returns a success status in json" do
        post :create, params: valid_payload, as: :json
        json = JSON.parse(response.body, symbolize_names: true)
        
        expect(json[:event_id]).to eq(valid_payload[:event_id])
        expect(json[:status]).to eq("accepted")
        expect(json[:message]).to eq("Event successfully queued for ingestion.")
      end

      it "publishes the event through LeadEvents::Producer" do
        expect {
          post :create, params: valid_payload, as: :json
        }.to change { LeadEvents::Producer.mock_queue.size }.by(1)
        
        published = LeadEvents::Producer.mock_queue.last
        expect(published[:event_id]).to eq(valid_payload[:event_id])
        expect(published[:event_type]).to eq(valid_payload[:event_type])
      end

      it "increments Yabeda events_ingested counter" do
        # We check that Yabeda increment is triggered
        expect(Yabeda.rd_marketing.events_ingested).to receive(:increment).with(
          { event_type: "page_view" }
        )
        post :create, params: valid_payload, as: :json
      end
    end

    context "with invalid parameters" do
      it "returns http unprocessable_entity" do
        post :create, params: invalid_payload, as: :json
        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "returns validation errors in response" do
        post :create, params: invalid_payload, as: :json
        json = JSON.parse(response.body, symbolize_names: true)

        expect(json).to have_key(:errors)
        expect(json[:errors][:event_id]).to include("must be a valid UUID")
        expect(json[:errors][:event_type]).to include("must be filled")
      end

      it "does not publish the event to the producer" do
        expect {
          post :create, params: invalid_payload, as: :json
        }.not_to change { LeadEvents::Producer.mock_queue.size }
      end

      it "increments Yabeda validation_failures counter" do
        expect(Yabeda.rd_marketing.validation_failures).to receive(:increment).with(
          { reason: "invalid_schema" }
        )
        post :create, params: invalid_payload, as: :json
      end
    end

    context "when producer raises an exception" do
      before do
        allow(LeadEvents::Producer).to receive(:publish).and_raise(StandardError.new("Kafka cluster down"))
      end

      it "returns internal server error status" do
        post :create, params: valid_payload, as: :json
        expect(response).to have_http_status(:internal_server_error)
      end

      it "returns error message in json" do
        post :create, params: valid_payload, as: :json
        json = JSON.parse(response.body, symbolize_names: true)
        expect(json[:error]).to eq("Internal server error. The ingestion service is temporarily unavailable.")
      end

      it "increments Yabeda server_errors counter" do
        expect(Yabeda.rd_marketing.server_errors).to receive(:increment).with(
          { controller: "events", action: "create" }
        )
        post :create, params: valid_payload, as: :json
      end
    end
  end

  describe "GET #debug" do
    it "processes the mock queue and updates the databases" do
      LeadEvents::Producer.publish(valid_payload)

      get :debug, as: :json
      expect(response).to have_http_status(:ok)
      
      json = JSON.parse(response.body, symbolize_names: true)
      expect(json[:kafka_queue]).to be_empty # Drain simulation
      expect(json[:clickhouse_store].map { |e| e[:event_id] }).to include(valid_payload[:event_id])
      expect(json[:elasticsearch_store].map { |e| e[:event_id] }).to include(valid_payload[:event_id])
    end
  end


  describe "GET #search" do
    it "filters search results from Elasticsearch" do
      Elasticsearch::LeadEventRepository.clear_mock_store!
      event1 = valid_payload.merge(event_id: "11111111-1111-1111-1111-111111111111", properties: { contact_name: "Ana Silva", contact_email: "ana@corp.com" })
      event2 = valid_payload.merge(event_id: "22222222-2222-2222-2222-222222222222", properties: { contact_name: "Bruno Santos", contact_email: "bruno@corp.com" })
      
      Elasticsearch::LeadEventRepository.bulk_index([event1, event2])

      # Exact match
      get :search, params: { q: "Ana Silva" }, as: :json
      json = JSON.parse(response.body, symbolize_names: true)
      expect(json.map { |e| e[:event_id] }).to include(event1[:event_id])
      expect(json.map { |e| e[:event_id] }).not_to include(event2[:event_id])

      # Fuzzy match (Levenshtein distance <= 2)
      get :search, params: { q: "Ana Silv" }, as: :json
      json = JSON.parse(response.body, symbolize_names: true)
      expect(json.map { |e| e[:event_id] }).to include(event1[:event_id])
    end
  end

  describe "POST #clear" do
    it "clears all mock queues and stores" do
      LeadEvents::Producer.publish(valid_payload)
      Clickhouse::LeadEventRepository.bulk_insert([valid_payload])
      Elasticsearch::LeadEventRepository.bulk_index([valid_payload])

      post :clear, as: :json
      expect(response).to have_http_status(:ok)

      get :debug, as: :json
      json = JSON.parse(response.body, symbolize_names: true)
      expect(json[:kafka_queue]).to be_empty
      expect(json[:clickhouse_store]).to be_empty
      expect(json[:elasticsearch_store]).to be_empty
    end
  end
end

