Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # API Ingestion endpoints
  namespace :api do
    namespace :v1 do
      resources :events, only: [:create] do
        collection do
          get :debug
          post :clear
        end
      end

    end
  end
end
