# frozen_string_literal: true

require "securerandom"

module LeadEvents
  class BackgroundGenerator
    # Predefined profiles for realistic mock leads
    PRESETS = [
      { name: "Ana Silva", email: "ana.silva@agenciadigital.com", company: "Agência Digital" },
      { name: "Bruno Santos", email: "bruno.santos@growthmarketing.io", company: "Growth Marketing" },
      { name: "Gabriela Lima", email: "gabriela.lima@limaweb.com.br", company: "Lima Web" },
      { name: "Diego Souza", email: "diego.souza@leadops.com", company: "Lead Ops" },
      { name: "Elena Costa", email: "elena.costa@techsolutions.com", company: "Tech Solutions" },
      { name: "Camila Oliveira", email: "camila.oliveira@saasstartups.co", company: "SaaS Startups" },
      { name: "Felipe Almeida", email: "felipe.almeida@automations.io", company: "Automation Labs" },
      { name: "Mariana Rocha", email: "mariana.rocha@inboundgroup.com", company: "Inbound Group" }
    ].freeze

    JOURNEY_STEPS = [
      { event_type: "page_view", path: "/features", referrer: "google_search" },
      { event_type: "newsletter_signup", path: "/blog", referrer: "direct" },
      { event_type: "conversion", path: "/resources/ebook-rails", conversion_page: "Ebook Inbound", referrer: "email_campaign" },
      { event_type: "page_view", path: "/pricing", referrer: "internal_link" },
      { event_type: "add_to_cart", path: "/checkout", plan: "Enterprise Pro", referrer: "sales_card" }
    ].freeze

    class << self
      def start
        # Only run in development mode and if we want the generator active
        return unless Rails.env.development?
        return if @started

        @started = true
        Rails.logger.info("[LeadEvents::BackgroundGenerator] Starting background generator thread...")

        # We keep track of lead states in-memory:
        # lead_email => { lead_id: UUID, step_index: Integer }
        @lead_states = {}

        Thread.new do
          # Delay initial start slightly to let the server boot fully
          sleep 5

          while true
            begin
              tick
            rescue => e
              Rails.logger.error("[LeadEvents::BackgroundGenerator] Error in tick: #{e.message}")
            end
            
            # Wait for a random interval between 15 and 30 seconds
            sleep(rand(15..30))
          end
        end
      end

      private

      def tick
        # Pick a random preset profile
        profile = PRESETS.sample
        
        # Initialize or retrieve state
        state = @lead_states[profile[:email]] ||= {
          lead_id: SecureRandom.uuid,
          step_index: 0
        }

        step = JOURNEY_STEPS[state[:step_index]]

        # Generate event
        event = {
          event_id: SecureRandom.uuid,
          lead_id: state[:lead_id],
          event_type: step[:event_type],
          timestamp: Time.now.utc.iso8601(3),
          properties: {
            contact_name: profile[:name],
            contact_email: profile[:email],
            company_name: profile[:company],
            path: step[:path],
            referrer: step[:referrer]
          }
        }

        # Add step-specific properties
        if step[:event_type] == "conversion"
          event[:properties][:conversion_page] = step[:conversion_page]
        elsif step[:event_type] == "add_to_cart"
          event[:properties][:plan] = step[:plan]
        end

        Rails.logger.info("[LeadEvents::BackgroundGenerator] Generating fake event: #{event[:event_type]} for #{profile[:name]} (Step #{state[:step_index]+1}/5)")

        # Publish the event
        LeadEvents::Producer.publish(event)

        # Advance state
        state[:step_index] += 1
        if state[:step_index] >= JOURNEY_STEPS.size
          # Reset state (new UUID, back to step 0) after journey is finished
          @lead_states.delete(profile[:email])
        end
      end
    end
  end
end
