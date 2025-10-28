# ForecastsController
#
# Handles weather forecast requests and displays weather information.
# Provides caching functionality to reduce API calls and logs user searches
# for analytics and popular location tracking.
#
# Actions:
#   - index: Displays the search form
#   - show: Processes address input and displays weather results
#
# Features:
#   - Input validation for addresses
#   - Intelligent caching with postal code-based keys
#   - Search logging for analytics
#   - Error handling with user-friendly messages
class ForecastsController < ApplicationController
  # Displays the weather search form
  #
  # Renders the index template with a form for users to enter addresses.
  # No parameters required.
  def index
    # Render the search form
    render :index
  end

  # Processes weather search requests and displays results
  #
  # Workflow:
  #   1. Validates the provided address
  #   2. Checks cache for existing forecast data
  #   3. Fetches fresh data if not cached
  #   4. Logs the search for analytics
  #   5. Displays the weather results
  #
  # Parameters:
  #   address [String] - The address to get weather for
  #
  # Returns:
  #   - Renders show template with weather data on success
  #   - Redirects to index with error message on failure
  #
  # Instance Variables:
  #   @forecast [Hash] - Weather data including current conditions and forecast
  #   @from_cache [Boolean] - Indicates if data was served from cache
  def show
    address = params[:address].to_s.strip
    
    # Validate address input
    unless valid_address?(address)
      flash[:alert] = I18n.t('weather.errors.invalid_address')
      redirect_to root_path and return
    end

    # Fetch weather data
    @forecast = fetch_weather_data(address)
    
    # Handle empty forecast (API failure)
    if @forecast.empty?
      flash[:alert] = I18n.t('weather.errors.no_data')
      redirect_to root_path and return
    end

    # Log the search for analytics
    WeatherSearch.log_search(address, @forecast[:postal_code])
    
    # Render the weather results
    render :show

  rescue StandardError => e
    Rails.logger.error "Forecast error for '#{address}': #{e.message}"
    flash[:alert] = I18n.t('weather.errors.fetch_error', error_message: e.message)
    redirect_to root_path
  end

  private

  # Validates that the provided address is acceptable
  #
  # @param address [String] The address to validate
  # @return [Boolean] true if address is valid, false otherwise
  def valid_address?(address)
    address.present? && address.length > 2
  end

  # Fetches weather data with caching support
  #
  # Checks cache first, then fetches from API if needed.
  # Uses postal code as primary cache key for better efficiency.
  #
  # @param address [String] The address to get weather for
  # @return [Hash] Weather forecast data
  def fetch_weather_data(address)
    # First, try address-based cache
    service = WeatherService.new(address)
    forecast = service.geocode_address

    postal_cache_key = forecast[:postal_code].present? ? "weather:postal:#{forecast[:postal_code]}" : nil
    address_cache_key = address.parameterize.present? ? "weather:addr:#{address.parameterize}" : nil
    if Rails.cache.exist?(postal_cache_key) || Rails.cache.exist?(address_cache_key)
      @from_cache = true  
      return Rails.cache.read(postal_cache_key) || Rails.cache.read(address_cache_key)
    end
    
    # If not in cache, fetch fresh data
    @from_cache = false
    service = WeatherService.new(address)
    forecast = service.fetch_forecast
    
    # Return empty hash if no data
    return {} if forecast.empty?
    
    # Generate optimal cache key based on postal code or address
    cache_key = postal_cache_key || address_cache_key
    
    # Cache the result for 30 minutes
    Rails.cache.write(cache_key, forecast, expires_in: 30.minutes) if cache_key.present?
    
    forecast
  end
end
