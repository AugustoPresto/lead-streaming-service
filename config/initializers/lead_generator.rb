# frozen_string_literal: true

Rails.application.config.after_initialize do
  # Start the background generator to stream mock actions over time in development
  if defined?(Rails::Server) || ENV["START_GENERATOR"] == "true"
    LeadEvents::BackgroundGenerator.start
  end
end
