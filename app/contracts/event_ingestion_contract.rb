# frozen_string_literal: true

require "dry-validation"

class EventIngestionContract < Dry::Validation::Contract
  UUID_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i
  ISO8601_REGEX = /\A\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:?\d{2})\z/

  params do
    required(:event_id).filled(:string)
    required(:lead_id).filled(:string)
    required(:event_type).filled(:string)
    required(:timestamp).filled(:string)
    optional(:properties).maybe(:hash)
  end

  rule(:event_id) do
    key.failure("must be a valid UUID") unless UUID_REGEX.match?(value)
  end

  rule(:lead_id) do
    key.failure("must be a valid UUID") unless UUID_REGEX.match?(value)
  end

  rule(:timestamp) do
    key.failure("must be a valid ISO8601 datetime string") unless ISO8601_REGEX.match?(value)
  end
end
