require 'rails_helper'

RSpec.describe ForecastsController, type: :controller do
  render_views
  let(:forecast_data) do
    {
      address: "New York, NY",
      postal_code: "10001",
      current: { temperature: 25, windspeed: 10 },
      forecast: [{ date: "2025-01-28", high: 28, low: 22, precipitation: 0, snowfall: 0, windspeed: 15 }]
    }
  end

  before do
    Rails.cache.clear
    allow_any_instance_of(WeatherService).to receive(:fetch_forecast).and_return(forecast_data)
  end

  describe 'GET #index' do
    it 'renders the index template' do
      get :index, format: :html
      expect(response).to have_http_status(:ok)
      expect(response).to render_template(:index)
    end
  end

  describe 'POST #show' do
    context 'with valid address' do
      it 'returns success and logs the search' do
        expect(WeatherSearch).to receive(:log_search).with("New York, NY", "10001").and_return(WeatherSearch.new)
        
        post :show, params: { address: 'New York, NY' }, format: :html
        
        puts "Response status: #{response.status}"
        puts "Response location: #{response.location}"
        puts "Flash messages: #{flash}"
        
        expect(response).to have_http_status(:ok)
        expect(response).to render_template(:show)
        expect(assigns(:forecast)).to eq(forecast_data)
      end

      it 'uses cached data when available via address key' do
        Rails.cache.write("weather:addr:new-york-ny", forecast_data, expires_in: 30.minutes)
        
        post :show, params: { address: 'New York, NY' }, format: :html
        
        expect(response).to have_http_status(:ok)
        expect(assigns(:from_cache)).to be true
      end

      it 'uses cached data when available via postal code key' do
        Rails.cache.write("weather:postal:10001", forecast_data, expires_in: 30.minutes)
        
        post :show, params: { address: 'New York, NY' }, format: :html
        
        expect(response).to have_http_status(:ok)
        expect(assigns(:from_cache)).to be true
      end

      it 'fetches fresh data when not cached and caches with both keys' do
        post :show, params: { address: 'New York, NY' }, format: :html
        
        expect(response).to have_http_status(:ok)
        expect(assigns(:from_cache)).to be false
        
        # Check that both cache keys are written
        expect(Rails.cache.read("weather:addr:new-york-ny")).to eq(forecast_data)
        expect(Rails.cache.read("weather:postal:10001")).to eq(forecast_data)
      end

      it 'handles empty forecast data gracefully' do
        allow_any_instance_of(WeatherService).to receive(:fetch_forecast).and_return({})
        
        post :show, params: { address: 'New York, NY' }, format: :html
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end
    end

    context 'with invalid address' do
      it 'redirects with error for blank address' do
        post :show, params: { address: '' }, format: :html
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end

      it 'redirects with error for short address' do
        post :show, params: { address: 'NY' }, format: :html
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to be_present
      end
    end

    context 'when WeatherService raises an error' do
      it 'redirects with error message' do
        allow_any_instance_of(WeatherService).to receive(:fetch_forecast).and_raise(StandardError, "API Error")
        
        post :show, params: { address: 'New York, NY' }, format: :html
        
        expect(response).to redirect_to(root_path)
        expect(flash[:alert]).to include("API Error")
      end
    end
  end
end
