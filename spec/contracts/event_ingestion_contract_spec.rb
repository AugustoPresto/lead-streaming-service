# frozen_string_literal: true

require "rails_helper"

RSpec.describe EventIngestionContract do
  subject(:contract) { described_class.new }

  let(:valid_attributes) do
    {
      event_id: "a0eebc99-9c0b-4ef8-bb6d-6bb9bd380a11",
      lead_id: "550e8400-e29b-41d4-a716-446655440000",
      event_type: "conversion",
      timestamp: "2026-06-26T12:00:00Z",
      properties: {
        page_url: "https://rdstation.com/blog",
        form_id: "newsletter-signup"
      }
    }
  end

  it "is valid with correct attributes" do
    result = contract.call(valid_attributes)
    expect(result).to be_success
  end

  it "fails if event_id is missing" do
    result = contract.call(valid_attributes.except(:event_id))
    expect(result).not_to be_success
    expect(result.errors[:event_id]).to include("is missing")
  end

  it "fails if event_id is not a valid UUID" do
    result = contract.call(valid_attributes.merge(event_id: "invalid-uuid"))
    expect(result).not_to be_success
    expect(result.errors[:event_id]).to include("must be a valid UUID")
  end

  it "fails if lead_id is not a valid UUID" do
    result = contract.call(valid_attributes.merge(lead_id: "123-abc"))
    expect(result).not_to be_success
    expect(result.errors[:lead_id]).to include("must be a valid UUID")
  end

  it "fails if event_type is empty" do
    result = contract.call(valid_attributes.merge(event_type: ""))
    expect(result).not_to be_success
    expect(result.errors[:event_type]).to include("must be filled")
  end

  it "fails if timestamp is not ISO8601" do
    result = contract.call(valid_attributes.merge(timestamp: "2026/06/26 12:00:00"))
    expect(result).not_to be_success
    expect(result.errors[:timestamp]).to include("must be a valid ISO8601 datetime string")
  end

  it "passes if properties is missing or nil (optional)" do
    result = contract.call(valid_attributes.except(:properties))
    expect(result).to be_success
  end
end
