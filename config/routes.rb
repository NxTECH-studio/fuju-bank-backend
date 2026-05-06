Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  resources :users, only: %i[show] do
    collection do
      get :me, to: "users#show_me"
      post :me, to: "users#upsert_me"
    end
    resources :transactions, only: %i[index], controller: "user_transactions"
  end

  resources :artifacts, only: %i[create show]

  post "ledger/mint", to: "ledger#mint"
  post "ledger/transfer", to: "ledger#transfer"

  # Defines the root path route ("/")
  # root "posts#index"
end
