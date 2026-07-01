Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  root to: ->(env) { [200, { "Content-Type" => "application/json" }, [{ status: "online", message: "Welcome to the Lead Ingestion & Analytics Streaming Service API", version: "v1", endpoints: { health: "/up", debug: "/api/v1/events/debug", ingest_events: "/api/v1/events [POST]" } }.to_json]] }

  # API Ingestion endpoints
  namespace :api do
    namespace :v1 do
      resources :events, only: [:create] do
        collection do
          get :debug
          get :search
          post :clear
        end
      end

    end
  end
end
