require 'rails_helper'

RSpec.describe WeatherService, type: :service do
  let(:address) { "New York, NY" }
  let(:service) { WeatherService.new(address) }

  describe '#fetch_forecast' do
    it 'returns forecast data hash with required keys' do
      # Mock the geocoding response
      allow(service).to receive(:geocode_address).and_return({
        lat: "40.7128",
        lon: "-74.0060",
        postal_code: "10001"
      })

      # Mock the weather API response
      weather_response = {
        'current_weather' => { 'temperature' => 25.5, 'windspeed' => 10.2 },
        'daily' => {
          'time' => ['2025-01-28', '2025-01-29', '2025-01-30'],
          'temperature_2m_max' => [28.0, 26.0, 24.0],
          'temperature_2m_min' => [22.0, 20.0, 18.0],
          'precipitation_sum' => [0.0, 1.5, 0.0],
          'snowfall_sum' => [0.0, 0.0, 0.0],
          'windspeed_10m_max' => [15.0, 12.0, 8.0]
        }
      }

      # Mock Net::HTTP.get for weather API
      allow(Net::HTTP).to receive(:get).and_return(weather_response.to_json)

      result = service.fetch_forecast

      expect(result).to include(:address, :postal_code, :current, :forecast)
      expect(result[:address]).to eq(address)
      expect(result[:postal_code]).to eq("10001")
      expect(result[:current]).to include(:temperature, :windspeed)
      expect(result[:forecast]).to be_an(Array)
      expect(result[:forecast].length).to eq(3)
      expect(result[:forecast].first).to include(:date, :high, :low, :precipitation, :snowfall, :windspeed)
    end

    it 'handles empty address gracefully' do
      empty_service = WeatherService.new("")
      result = empty_service.fetch_forecast
      expect(result).to eq({})
    end

    it 'handles nil address gracefully' do
      nil_service = WeatherService.new(nil)
      result = nil_service.fetch_forecast
      expect(result).to eq({})
    end

    it 'handles geocoding errors gracefully' do
      allow(service).to receive(:geocode_address).and_return({})
      result = service.fetch_forecast
      expect(result).to eq({})
    end

    it 'handles geocoding with missing coordinates' do
      allow(service).to receive(:geocode_address).and_return({
        lat: nil,
        lon: nil,
        postal_code: "10001"
      })
      result = service.fetch_forecast
      expect(result).to eq({})
    end

    it 'handles weather API errors gracefully' do
      allow(service).to receive(:geocode_address).and_return({
        lat: "40.7128",
        lon: "-74.0060",
        postal_code: "10001"
      })

      # Mock API error response
      allow(Net::HTTP).to receive(:get).and_return({
        'error' => true,
        'reason' => 'Invalid coordinates'
      }.to_json)

      result = service.fetch_forecast
      expect(result).to eq({})
    end

    it 'handles malformed weather API response' do
      allow(service).to receive(:geocode_address).and_return({
        lat: "40.7128",
        lon: "-74.0060",
        postal_code: "10001"
      })

      # Mock malformed response
      allow(Net::HTTP).to receive(:get).and_return({
        'current_weather' => { 'temperature' => 25.5, 'windspeed' => 10.2 }
        # Missing 'daily' key
      }.to_json)

      result = service.fetch_forecast
      expect(result).to eq({})
    end

    it 'handles network errors gracefully' do
      allow(service).to receive(:geocode_address).and_return({
        lat: "40.7128",
        lon: "-74.0060",
        postal_code: "10001"
      })

      # Mock network error
      allow(Net::HTTP).to receive(:get).and_raise(StandardError, "Network error")

      result = service.fetch_forecast
      expect(result).to eq({})
    end
  end

  describe '#geocode_address' do
    it 'returns geocoding data for valid address' do
      # Mock successful geocoding response
      geocoding_response = [{
        'lat' => '40.7128',
        'lon' => '-74.0060',
        'address' => {
          'postcode' => '10001'
        }
      }]

      # Mock Net::HTTP for geocoding
      http_double = double('http')
      request_double = double('request')
      response_double = double('response', body: geocoding_response.to_json)

      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(Net::HTTP::Get).to receive(:new).and_return(request_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:request).and_return(response_double)
      allow(request_double).to receive(:[]=) # Allow setting User-Agent header

      result = service.send(:geocode_address)

      expect(result).to include(:lat, :lon, :postal_code)
      expect(result[:lat]).to eq('40.7128')
      expect(result[:lon]).to eq('-74.0060')
      expect(result[:postal_code]).to eq('10001')
    end

    it 'handles empty geocoding results' do
      # Mock empty geocoding response
      http_double = double('http')
      request_double = double('request')
      response_double = double('response', body: [].to_json)

      allow(Net::HTTP).to receive(:new).and_return(http_double)
      allow(Net::HTTP::Get).to receive(:new).and_return(request_double)
      allow(http_double).to receive(:use_ssl=)
      allow(http_double).to receive(:request).and_return(response_double)
      allow(request_double).to receive(:[]=)

      result = service.send(:geocode_address)
      expect(result).to eq({})
    end

    it 'handles geocoding network errors' do
      # Mock network error
      allow(Net::HTTP).to receive(:new).and_raise(StandardError, "Network error")

      result = service.send(:geocode_address)
      expect(result).to eq({})
    end
  end
end
