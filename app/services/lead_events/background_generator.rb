# frozen_string_literal: true

require "securerandom"

module LeadEvents
  class BackgroundGenerator
    # Predefined profiles for realistic mock leads
    FIRST_NAMES = %w[Ana Bruno Gabriela Diego Elena Camila Felipe Mariana Lucas Julia Rodrigo Beatriz Thiago Larissa Gustavo Amanda Rafael Isabela Andre Carolina].freeze
    LAST_NAMES = %w[Silva Santos Lima Souza Costa Oliveira Almeida Rocha Pereira Ferreira Rodrigues Gomes Martins Araujo Ribeiro Carvalho Cardoso Teixeira Moreira Nogueira].freeze
    COMPANIES = ["Growth Corp", "Tech Solutions", "SaaS Startups", "Automation Labs", "Inbound Group", "Devs Corp", "Cloud Services", "Analytics Pro", "Marketing Hub", "Sales Flow", "Lead Operations", "FinTech Hub", "Web Solutions"].freeze

    JOURNEY_STEPS = [
      { event_type: "page_view", path: "/features", referrer: "google_search" },
      { event_type: "newsletter_signup", path: "/blog", referrer: "direct" },
      { event_type: "conversion", path: "/resources/ebook-rails", conversion_page: "Ebook Inbound", referrer: "email_campaign" },
      { event_type: "page_view", path: "/pricing", referrer: "internal_link" },
      { event_type: "add_to_cart", path: "/checkout", plan: "Enterprise Pro", referrer: "sales_card" }
    ].freeze

    class << self
      def start
        # Run in development or if explicitly enabled via environment variable
        return unless Rails.env.development? || ENV["START_GENERATOR"] == "true"
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
        active_emails = @lead_states.keys
        # Maintain up to 50 active concurrent lead journeys.
        # If we have less, we have a 40% chance to start a brand new lead, otherwise we continue an active one.
        should_start_new = active_emails.empty? || (active_emails.size < 50 && rand < 0.4)

        if should_start_new
          first_name = FIRST_NAMES.sample
          last_name = LAST_NAMES.sample
          company = COMPANIES.sample
          name = "#{first_name} #{last_name}"
          
          # Generate clean, realistic, and unique email
          email_prefix = "#{first_name.downcase}.#{last_name.downcase}#{rand(10..99)}"
          domain = company.downcase.gsub(/[^a-z0-9]/, "")
          email = "#{email_prefix}@#{domain}.com"
          
          profile = { name: name, email: email, company: company }
          
          state = @lead_states[email] = {
            lead_id: SecureRandom.uuid,
            step_index: 0,
            profile: profile
          }
        else
          email = active_emails.sample
          state = @lead_states[email]
          profile = state[:profile]
        end

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
