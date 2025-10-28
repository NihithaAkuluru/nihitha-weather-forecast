Rails.application.routes.draw do
  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  
  root 'forecasts#index'
  post 'forecast', to: 'forecasts#show', as: :forecast
end
