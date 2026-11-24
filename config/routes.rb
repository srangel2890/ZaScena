Rails.application.routes.draw do

  Rails.application.routes.draw do
    namespace :api do
      namespace :v1 do
                post "/login", to: "auth#login"
        resources :events, only: [:index, :show, :create, :update, :destroy]
        resources :reservations, only: [:index, :show, :create]
        
        get 'users/:user_id/reservations', to: 'reservations#by_user'
      end
    end
  end
end
