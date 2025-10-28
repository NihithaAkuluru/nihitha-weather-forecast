class ForecastRefresherWorker
  include Sidekiq::Worker
  sidekiq_options retry: 3, queue: :default

  #
  # This Sidekiq worker automatically refreshes cached weather forecast data
  # for the top 3 most searched locations. It ensures that users receive updated
  # weather information for popular locations without repeatedly calling external APIs.
  #
  # The worker is designed to operate only during business hours
  # (between 6:00 AM and 9:00 PM, server timezone) to optimize API usage
  # and reduce unnecessary background processing during off-hours.
  #
  # Workflow:
  #   1. Checks current server time.
  #   2. Runs only if the time is between 6 AM and 9 PM.
  #   3. Fetches the top 3 most searched locations from WeatherSearch model.
  #   4. Uses WeatherService to fetch the latest forecast data for each location.
  #   5. Writes the refreshed forecasts into the Rails cache with a 30-minute TTL.
  #   6. Errors (e.g., network or API issues) are logged but do not cause retries beyond the default limit.
  #
  # Example:
  #   ForecastRefresherWorker.perform_async
  #
  # Notes:
  #   - This job is typically scheduled via cron every 30 minutes.
  #   - It automatically processes the most popular search locations.
  #   - No parameters needed - it determines locations from the database.
  def perform
    current_hour = Time.zone.now.hour

    # Only run between 6 AM and 9 PM
    return unless current_hour.between?(6, 21)

    # Get top 3 most searched locations
    popular_searches = WeatherSearch.popular_searches(3)
    
    if popular_searches.empty?
      Rails.logger.info "ForecastRefresherWorker: No search data found to refresh"
      return
    end

    Rails.logger.info "ForecastRefresherWorker: Refreshing forecasts for #{popular_searches.count} popular locations"

    popular_searches.each do |search_data|
      address = search_data.address
      postal_code = search_data.postal_code

      begin
        service = WeatherService.new(address)
        forecast = service.fetch_forecast

        # Use postal code for cache key if available, otherwise use address
        cache_key = postal_code.present? ? "weather:postal:#{postal_code}" : "weather:addr:#{address.parameterize}"

        Rails.cache.write(cache_key, forecast, expires_in: 30.minutes)
        Rails.logger.info "ForecastRefresherWorker: Successfully refreshed forecast for #{address}"
        
      rescue StandardError => e
        Rails.logger.error "ForecastRefresherWorker failed for #{address}: #{e.message}"
      end
    end

    Rails.logger.info "ForecastRefresherWorker: Completed refreshing popular location forecasts"
  rescue StandardError => e
    Rails.logger.error "ForecastRefresherWorker failed: #{e.message}"
  end
end
