require 'rails_helper'

RSpec.describe ForecastRefresherWorker, type: :worker do
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
    # Create some sample weather searches
    WeatherSearch.create!(address: "New York, NY", postal_code: "10001", count: 10, searched_at: Time.current)
    WeatherSearch.create!(address: "London, UK", postal_code: "SW1A 1AA", count: 8, searched_at: Time.current)
    WeatherSearch.create!(address: "Tokyo, Japan", postal_code: "100-0001", count: 5, searched_at: Time.current)
  end

  describe '#perform' do
    it 'refreshes forecasts for top 3 popular searches' do
      # Mock WeatherService to return forecast data
      weather_service_double = double('WeatherService')
      allow(WeatherService).to receive(:new).and_return(weather_service_double)
      allow(weather_service_double).to receive(:fetch_forecast).and_return(forecast_data)

      # Mock time to be within business hours
      allow(Time.zone).to receive(:now).and_return(Time.zone.parse("2025-01-28 12:00:00"))

      # Run the worker
      described_class.new.perform

      # Check that WeatherService was called for each popular location
      expect(weather_service_double).to have_received(:fetch_forecast).exactly(3).times
      
      # Check that cache was updated for popular locations (using postal code keys)
      expect(Rails.cache.read("weather:postal:10001")).to eq(forecast_data)
      expect(Rails.cache.read("weather:postal:SW1A 1AA")).to eq(forecast_data)
      expect(Rails.cache.read("weather:postal:100-0001")).to eq(forecast_data)
    end

    it 'handles locations without postal codes by using address keys' do
      # Clear existing searches and create one without postal code
      WeatherSearch.destroy_all
      WeatherSearch.create!(address: "Unknown Location", postal_code: nil, count: 15, searched_at: Time.current)
      
      # Mock WeatherService to return forecast data without postal code
      forecast_without_postal = forecast_data.dup
      forecast_without_postal[:postal_code] = nil
      
      weather_service_double = double('WeatherService')
      allow(WeatherService).to receive(:new).and_return(weather_service_double)
      allow(weather_service_double).to receive(:fetch_forecast).and_return(forecast_without_postal)

      # Mock time to be within business hours
      allow(Time.zone).to receive(:now).and_return(Time.zone.parse("2025-01-28 12:00:00"))

      # Run the worker
      described_class.new.perform

      # Check that cache was updated using address key for location without postal code
      expect(Rails.cache.read("weather:addr:unknown-location")).to eq(forecast_without_postal)
    end

    it 'handles case when no popular searches exist' do
      # Clear all weather searches
      WeatherSearch.destroy_all
      
      # Mock time to be within business hours
      allow(Time.zone).to receive(:now).and_return(Time.zone.parse("2025-01-28 12:00:00"))

      # Should not call WeatherService
      expect_any_instance_of(WeatherService).not_to receive(:fetch_forecast)

      # Should log appropriate message
      expect(Rails.logger).to receive(:info).with("ForecastRefresherWorker: No search data found to refresh")

      described_class.new.perform
    end

    it 'does not run outside business hours' do
      # Mock time to be outside business hours
      allow(Time.zone).to receive(:now).and_return(Time.zone.parse("2025-01-28 23:00:00"))

      # Should not call WeatherService
      weather_service_double = double('WeatherService')
      allow(WeatherService).to receive(:new).and_return(weather_service_double)
      expect(weather_service_double).not_to receive(:fetch_forecast)

      described_class.new.perform
    end

    it 'handles errors gracefully' do
      # Mock WeatherService to raise an error
      weather_service_double = double('WeatherService')
      allow(WeatherService).to receive(:new).and_return(weather_service_double)
      allow(weather_service_double).to receive(:fetch_forecast).and_raise(StandardError, "API Error")

      # Mock time to be within business hours
      allow(Time.zone).to receive(:now).and_return(Time.zone.parse("2025-01-28 12:00:00"))

      # Should not raise an error
      expect { described_class.new.perform }.not_to raise_error
    end

    it 'logs appropriate messages' do
      weather_service_double = double('WeatherService')
      allow(WeatherService).to receive(:new).and_return(weather_service_double)
      allow(weather_service_double).to receive(:fetch_forecast).and_return(forecast_data)
      allow(Time.zone).to receive(:now).and_return(Time.zone.parse("2025-01-28 12:00:00"))

      # Allow other log messages but check for specific ones
      allow(Rails.logger).to receive(:info)
      
      expect(Rails.logger).to receive(:info).with(/Refreshing forecasts for 3 popular locations/)
      expect(Rails.logger).to receive(:info).with(/Successfully refreshed forecast for New York, Ny/)
      expect(Rails.logger).to receive(:info).with(/Completed refreshing popular location forecasts/)

      described_class.new.perform
    end
  end
end
