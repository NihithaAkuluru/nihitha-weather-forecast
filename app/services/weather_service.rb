require 'net/http'
require 'json'

# WeatherService
#
# This service class handles fetching weather details for a given address.
# It performs two key tasks:
#   1. Geocoding the input address using the OpenStreetMap Nominatim API
#      to retrieve latitude, longitude, and postal code.
#   2. Fetching current weather and 3-day forecast data (temperature,
#      precipitation, snowfall, etc.) from the Open-Meteo API.
#
# The service is designed for simplicity and modularity — suitable for use
# in background jobs, controllers, or other service objects.
class WeatherService
  WEATHER_BASE_URL = 'https://api.open-meteo.com/v1/forecast'.freeze
  GEO_BASE_URL = 'https://nominatim.openstreetmap.org/search'.freeze
  GOOGLE_GEOCODING_URL = 'https://maps.googleapis.com/maps/api/geocode/json'.freeze
  GEOAPIFY_URL = 'https://api.geoapify.com/v1/geocode/search'.freeze

  def initialize(address)
    @address = address
  end

  # Fetches the current weather and 3-day forecast for a given address.
  #
  # Workflow:
  #   1. Geocodes the provided address to obtain latitude, longitude, and postal code.
  #   2. Queries the Open-Meteo API to retrieve:
  #        - Current temperature and wind speed (real-time)
  #        - 3-day daily forecast data including:
  #            - Maximum and minimum temperatures (°C)
  #            - Total precipitation (mm)
  #            - Total snowfall (cm)
  #            - Maximum windspeed at 10m height (km/h)
  #
  # Returns:
  #   A structured hash in the following format:
  #
  #     {
  #       address: "Bangalore, India",
  #       postal_code: "560001",
  #       current: {
  #         temperature: 28.5,
  #         windspeed: 5.2
  #       },
  #       forecast: [
  #         {
  #           date: "2025-10-27",
  #           high: 31.2,
  #           low: 22.8,
  #           precipitation: 0.4,
  #           snowfall: 0.0,
  #           windspeed: 15.6
  #         },
  #         {
  #           date: "2025-10-28",
  #           high: 30.8,
  #           low: 21.9,
  #           precipitation: 1.1,
  #           snowfall: 0.0,
  #           windspeed: 12.3
  #         },
  #         ...
  #       ]
  #     }
  def fetch_forecast
    geocode = geocode_address
    return {} if geocode.empty? || geocode[:lat].nil? || geocode[:lon].nil?

    params = {
      latitude: geocode[:lat],
      longitude: geocode[:lon],
      current_weather: true,
      daily: 'temperature_2m_max,temperature_2m_min,precipitation_sum,snowfall_sum,windspeed_10m_max',
      forecast_days: 3,
      timezone: 'auto'
    }

    uri = URI(WEATHER_BASE_URL)
    uri.query = URI.encode_www_form(params)
    
    begin
      response = Net::HTTP.get(uri)
      data = JSON.parse(response)
    rescue StandardError => e
      Rails.logger.error "Weather API request failed: #{e.message}"
      return {}
    end
    # Handle API errors
    return {} if data['error'] || data['daily'].nil?

    daily_data = data['daily']
    days = daily_data['time'].each_with_index.map do |date, i|
      {
        date: date,
        high: daily_data['temperature_2m_max'][i],
        low: daily_data['temperature_2m_min'][i],
        precipitation: daily_data['precipitation_sum'][i],
        snowfall: daily_data['snowfall_sum'][i],
        windspeed: daily_data['windspeed_10m_max'][i]
      }
    end

    {
      address: @address,
      postal_code: geocode[:postal_code],
      current: {
        temperature: data.dig('current_weather', 'temperature'),
        windspeed: data.dig('current_weather', 'windspeed')
      },
      forecast: days
    }
  end

  # Geocodes an address using Geoapify API with fallback to Nominatim
  #
  # Converts a given address into geographical coordinates (latitude and longitude)
  # and extracts the postal code. Uses Geoapify API for excellent postal code
  # reliability, with fallback to OpenStreetMap Nominatim API.
  #
  # @return [Hash] Hash containing lat, lon, and postal_code keys
  # @return [Hash] Empty hash if geocoding fails
  #
  # Example:
  #   @address = "New York, NY"
  #   geocode_address
  #   => { lat: "40.7127281", lon: "-74.0060152", postal_code: "10001" }
  #
  # Notes:
  #   - Returns empty hash if address is nil or empty
  #   - Tries Geoapify API first (excellent postal code coverage)
  #   - Falls back to Nominatim if Geoapify fails
  #   - Geoapify provides very reliable postal codes
  def geocode_address
    return {} if @address.nil? || @address.strip.empty?

    # Try Geoapify API first (excellent postal code coverage)
    geoapify_result = geocode_with_geoapify
    return geoapify_result if geoapify_result.present?

    # Fallback to Nominatim (always works)
    Rails.logger.info "Using Nominatim for '#{@address}'"
    geocode_with_nominatim
  end

  private

  # Geocodes using Geoapify API (3k free requests/day)
  def geocode_with_geoapify
    api_key = ENV['GEOAPIFY_API_KEY']
    return {} if api_key.blank?

    uri = URI(GEOAPIFY_URL)
    uri.query = URI.encode_www_form(
      text: @address,
      limit: 1,
      format: 'json',
      apiKey: api_key
    )
    
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri)
      
      response = http.request(request)
      data = JSON.parse(response.body)
      
      return {} if data['results'].empty?
      
      result = data['results'].first
      
      Rails.logger.info "Geoapify Geocoding '#{@address}' -> Postal: #{result['postcode'] || 'none'}, Lat: #{result['lat']}, Lon: #{result['lon']}"
      
      {
        lat: result['lat'].to_s,
        lon: result['lon'].to_s,
        postal_code: result['postcode']
      }
    rescue StandardError => e
      Rails.logger.error "Geoapify Geocoding failed for '#{@address}': #{e.message}"
      {}
    end
  end

  # Geocodes using OpenStreetMap Nominatim API (fallback)
  def geocode_with_nominatim
    uri = URI(GEO_BASE_URL)
    uri.query = URI.encode_www_form(
      q: @address, 
      format: 'json', 
      limit: 5,
      addressdetails: 1,
      extratags: 1,
      namedetails: 1
    )
    
    begin
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      request = Net::HTTP::Get.new(uri)
      request['User-Agent'] = 'WeatherForecastApp/1.0'
      
      response = http.request(request)
      results = JSON.parse(response.body)
      return {} if results.empty?
      
      # Find the best result with postal code, or fallback to first result
      best_result = nil
      
      results.each do |result|
        postal_code = result.dig('address', 'postcode') ||
                     result.dig('address', 'postal_code') ||
                     result.dig('address', 'pincode') ||
                     result.dig('address', 'zipcode')
        
        if postal_code.present?
          best_result = result
          break
        end
      end
      
      best_result ||= results.first
      
      postal_code = best_result.dig('address', 'postcode') ||
                   best_result.dig('address', 'postal_code') ||
                   best_result.dig('address', 'pincode') ||
                   best_result.dig('address', 'zipcode')
      
      Rails.logger.info "Nominatim Geocoding '#{@address}' -> Postal: #{postal_code || 'none'}, Lat: #{best_result['lat']}, Lon: #{best_result['lon']}"
      
      {
        lat: best_result['lat'],
        lon: best_result['lon'],
        postal_code: postal_code
      }
    rescue StandardError => e
      Rails.logger.error "Nominatim Geocoding failed for '#{@address}': #{e.message}"
      {}
    end
  end

  # Extracts postal code from Google address components
  def extract_google_postal_code(address_components)
    postal_component = address_components.find { |component| 
      component['types'].include?('postal_code')
    }
    postal_component&.dig('long_name')
  end
end
