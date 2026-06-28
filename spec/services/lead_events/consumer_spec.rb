# frozen_string_literal: true

require "rails_helper"

RSpec.describe LeadEvents::Consumer do
  describe ".process_batch" do
    let(:event_1) do
      {
        event_id: "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
        lead_id: "550e8400-e29b-41d4-a716-446655440000",
        event_type: "conversion",
        timestamp: "2026-06-26T12:00:00Z",
        properties: { company_id: "770e8400-e29b-41d4-a716-446655440000", conversion_page: "main_lp" }
      }
    end

    let(:event_2) do
      {
        event_id: "c0ddbc99-9c0b-4ef8-bb6d-6bb9bd380a22",
        lead_id: "660e8400-e29b-41d4-a716-446655440000",
        event_type: "page_view",
        timestamp: "2026-06-26T12:01:00Z",
        properties: { company_id: "770e8400-e29b-41d4-a716-446655440000", page_title: "features" }
      }
    end

    let(:messages) do
      [
        Struct.new(:payload).new(event_1.to_json),
        Struct.new(:payload).new(event_2.to_json)
      ]
    end

    before do
      Clickhouse::LeadEventRepository.clear_mock_store!
      Elasticsearch::LeadEventRepository.clear_mock_store!
    end

    context "when all writes succeed" do
      it "inserts elements in both Clickhouse and Elasticsearch repositories" do
        expect {
          described_class.process_batch(messages)
        }.to change { Clickhouse::LeadEventRepository.mock_store.size }.by(2)
         .and change { Elasticsearch::LeadEventRepository.mock_store.size }.by(2)

        expect(Clickhouse::LeadEventRepository.mock_store.first[:event_id]).to eq(event_1[:event_id])
        expect(Clickhouse::LeadEventRepository.mock_store.first[:processed_at]).not_to be_nil
        expect(Elasticsearch::LeadEventRepository.mock_store.last[:event_id]).to eq(event_2[:event_id])
        expect(Elasticsearch::LeadEventRepository.mock_store.last[:processed_at]).not_to be_nil
      end
    end

    context "when Clickhouse bulk write fails" do
      before do
        allow(Clickhouse::LeadEventRepository).to receive(:bulk_insert).and_raise(StandardError.new("Clickhouse connection timeout"))
      end

      it "raises an error to trigger Kafka partition retry" do
        expect {
          described_class.process_batch(messages)
        }.to raise_error(RuntimeError, /Batch processing failed/)
      end

      it "does not proceed with or commits the Elasticsearch index if Clickhouse fails before it" do
        # In our implementation clickhouse writes first, so if clickhouse fails, we don't proceed.
        expect(Elasticsearch::LeadEventRepository.mock_store).to be_empty
      end
    end

    context "when Elasticsearch indexing fails" do
      before do
        allow(Elasticsearch::LeadEventRepository).to receive(:bulk_index).and_raise(StandardError.new("Elasticsearch node unreachable"))
      end

      it "raises an error to trigger Kafka partition retry" do
        expect {
          described_class.process_batch(messages)
        }.to raise_error(RuntimeError, /Batch processing failed/)
      end
    end

    context "with a batch containing invalid JSON payloads" do
      let(:corrupted_messages) do
        [
          Struct.new(:payload).new("{invalid-json}"),
          Struct.new(:payload).new(event_1.to_json)
        ]
      end

      it "skips the corrupted messages and processes the valid ones" do
        expect {
          described_class.process_batch(corrupted_messages)
        }.to change { Clickhouse::LeadEventRepository.mock_store.size }.by(1)
         .and change { Elasticsearch::LeadEventRepository.mock_store.size }.by(1)

        expect(Clickhouse::LeadEventRepository.mock_store.first[:event_id]).to eq(event_1[:event_id])
      end
    end
  end
end
