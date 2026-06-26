# frozen_string_literal: true

namespace :kafka do
  desc "Starts the Kafka consumer to stream lead events to ClickHouse and Elasticsearch"
  task consume_events: :environment do
    # Ensure logs flush immediately in containers
    $stdout.sync = true
    $stderr.sync = true

    Signal.trap("TERM") do
      puts "Received SIGTERM, shutting down consumer..."
      exit(0)
    end

    Signal.trap("INT") do
      puts "Received SIGINT, shutting down consumer..."
      exit(0)
    end

    begin
      LeadEvents::Consumer.start
    rescue => e
      Rails.logger.fatal("Kafka consumer task crashed: #{e.message}")
      Sentry.capture_exception(e)
      exit(1)
    end
  end
end
