# Weather Forecast Application

A Rails-based weather forecast application that provides current weather conditions and 3-day forecasts for any location worldwide. The application features intelligent caching, search analytics, and background job processing for optimal performance.

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Object Decomposition](#object-decomposition)
- [Design Patterns](#design-patterns)
- [API Integration](#api-integration)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
- [Testing](#testing)
- [Configuration](#configuration)

## Overview

This application provides a web interface for users to search for weather information by address. It integrates with external APIs to fetch real-time weather data and implements intelligent caching to reduce API calls and improve performance.

### Key Capabilities

-   Real-time Weather Data  : Current temperature and wind speed
-   3-Day Forecast  : Detailed daily forecasts including temperature ranges, precipitation, and snowfall
-   Advanced Geocoding  : Multiple geocoding APIs with postal code extraction (Geoapify + Nominatim fallback)
-   Intelligent Caching  : Postal code-priority caching system for maximum efficiency
-   Search Analytics  : Tracks popular search locations for optimization
-   Background Processing  : Automated refresh of popular location forecasts
-   Error Handling  : Graceful handling of API failures and invalid inputs
-   Environment Configuration  : Secure API key management

## Architecture

The application follows a clean, modular architecture with clear separation of concerns:

```
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│   Web Layer     │    │  Service Layer  │    │   Data Layer    │
│                 │    │                 │    │                 │
│ ForecastsController │◄──│ WeatherService  │◄──│ WeatherSearch   │
│                 │    │                 │    │                 │
│ Views (ERB)     │    │ External APIs   │    │ SQLite Database │
└─────────────────┘    └─────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌─────────────────┐    ┌─────────────────┐
│ Background Jobs │    │   Caching       │    │   Logging       │
│                 │    │                 │    │                 │
│ ForecastRefresher│    │ Rails Cache     │    │ Rails Logger    │
│ Worker           │    │ (Memory/File)   │    │                 │
└─────────────────┘    └─────────────────┘    └─────────────────┘
```

## Object Decomposition

### 1. WeatherSearch Model

  Purpose  : Manages weather search analytics and popular location tracking.

  Object Structure  :
```ruby
class WeatherSearch < ApplicationRecord
  # Attributes
  address: String        # Normalized address (e.g., "New York, Ny")
  postal_code: String    # Postal code from geocoding (e.g., "10001")
  count: Integer         # Number of times this location was searched
  searched_at: DateTime  # Timestamp of last search
end
```

  Responsibilities  :
-   Data Persistence  : Stores search history and analytics
-   Search Logging  : Increments count for existing searches or creates new records
-   Popular Location Retrieval  : Returns top searched locations ordered by count
-   Data Validation  : Ensures data integrity with validations
-   Address Normalization  : Standardizes address formatting

  Key Methods  :
```ruby
# Class Methods
WeatherSearch.log_search(address, postal_code)     # Logs a search
WeatherSearch.popular_searches(limit)              # Returns top N searches

# Instance Methods (inherited from ActiveRecord)
weather_search.save!                               # Persists to database
weather_search.increment!(:count)                  # Increments count field
```

  Dependencies  :
- `ApplicationRecord` (ActiveRecord base class)
- `Rails.logger` (for error logging)

---

### 2. WeatherService

  Purpose  : Handles external API integration for geocoding and weather data retrieval.

  Object Structure  :
```ruby
class WeatherService
  # Constants
  WEATHER_BASE_URL = 'https://api.open-meteo.com/v1/forecast'
  GEO_BASE_URL = 'https://nominatim.openstreetmap.org/search'
  
  # Instance Variables
  @address: String  # Input address to process
end
```

  Responsibilities  :
-   Geocoding  : Converts addresses to coordinates using OpenStreetMap Nominatim API
-   Weather Data Retrieval  : Fetches current and forecast data from Open-Meteo API
-   Data Transformation  : Converts API responses to standardized format
-   Error Handling  : Manages API failures gracefully
-   HTTP Communication  : Handles network requests with proper headers

  Key Methods  :
```ruby
# Public Methods
initialize(address)                    # Sets up service with address
fetch_forecast                        # Main method - returns complete weather data

# Private Methods
geocode_address                       # Converts address to coordinates
```

  Data Flow  :
```
Input: "New York, NY"
  ↓
geocode_address()
  ↓
OpenStreetMap Nominatim API
  ↓
{ lat: "40.7128", lon: "-74.0060", postal_code: "10001" }
  ↓
fetch_forecast()
  ↓
Open-Meteo API
  ↓
{
  address: "New York, NY",
  postal_code: "10001",
  current: { temperature: 25.5, windspeed: 10.2 },
  forecast: [
    { date: "2025-10-28", high: 28.0, low: 22.0, precipitation: 0.0, snowfall: 0.0, windspeed: 15.0 },
    ...
  ]
}
```

  Dependencies  :
- `Net::HTTP` (HTTP client)
- `JSON` (JSON parsing)
- `URI` (URL handling)
- `Rails.logger` (error logging)

---

### 3. ForecastsController

  Purpose  : Handles HTTP requests and coordinates the weather forecast workflow.

  Object Structure  :
```ruby
class ForecastsController < ApplicationController
  # Instance Variables (set during request processing)
  @forecast: Hash      # Weather data for display
  @from_cache: Boolean # Indicates if data came from cache
end
```

  Responsibilities  :
-   Request Handling  : Processes GET and POST requests
-   Input Validation  : Validates address parameters
-   Caching Logic  : Implements cache-first strategy
-   Search Logging  : Records user searches for analytics
-   Error Management  : Handles and displays user-friendly error messages
-   View Coordination  : Prepares data for template rendering

  Key Methods  :
```ruby
# Public Actions
index                    # Displays search form
show                     # Processes search and displays results

# Private Methods
valid_address?(address)           # Validates input address
fetch_weather_data(address)       # Handles caching and data retrieval
generate_cache_key(postal_code, address)  # Creates optimal cache keys
```

  Request Flow  :
```
POST /forecast
  ↓
show action
  ↓
valid_address?() → true/false
  ↓ (if true)
fetch_weather_data()
  ↓
Check cache → Hit/Miss
  ↓ (if miss)
WeatherService.fetch_forecast()
  ↓
Cache result
  ↓
WeatherSearch.log_search()
  ↓
Render show template
```

  Dependencies  :
- `ApplicationController` (Rails base controller)
- `WeatherService` (for data retrieval)
- `WeatherSearch` (for search logging)
- `Rails.cache` (for caching)
- `I18n` (for internationalization)

---

### 4. ForecastRefresherWorker

  Purpose  : Background job that refreshes cached weather data for popular locations.

  Object Structure  :
```ruby
class ForecastRefresherWorker
  include Sidekiq::Worker
  
  # Sidekiq Configuration
  sidekiq_options retry: 3, queue: :default
end
```

  Responsibilities  :
-   Scheduled Execution  : Runs automatically during business hours (6 AM - 9 PM)
-   Popular Location Processing  : Fetches top 3 most searched locations
-   Cache Refresh  : Updates cached weather data for popular locations
-   Error Handling  : Logs errors without failing the entire job
-   Performance Optimization  : Reduces API calls for frequently accessed locations

  Key Methods  :
```ruby
# Public Methods
perform                    # Main job execution method

# Workflow Steps (internal)
1. Check business hours
2. Get popular searches
3. Fetch fresh weather data
4. Update cache
5. Log results
```

  Execution Flow  :
```
Sidekiq Cron Trigger
  ↓
perform()
  ↓
Check time (6 AM - 9 PM)
  ↓ (if within hours)
WeatherSearch.popular_searches(3)
  ↓
For each location:
  WeatherService.fetch_forecast()
  ↓
  Rails.cache.write()
  ↓
Log success/error
```

  Dependencies  :
- `Sidekiq::Worker` (background job framework)
- `WeatherSearch` (for popular locations)
- `WeatherService` (for fresh data)
- `Rails.cache` (for cache updates)
- `Rails.logger` (for logging)

---

### 5. View Templates

  Purpose  : Present weather data to users with modern, responsive UI.

  Object Structure  :
```erb
<!-- app/views/forecasts/index.html.erb -->
<div class="weather-container">
  <div class="weather-header">...</div>
  <div class="search-form">...</div>
  <div class="alert">...</div>
</div>

<!-- app/views/forecasts/show.html.erb -->
<div class="weather-container">
  <div class="weather-header">...</div>
  <div class="current-weather">...</div>
  <div class="cache-status">...</div>
  <div class="forecast-section">...</div>
</div>
```

  Responsibilities  :
-   User Interface  : Provides intuitive search form and results display
-   Data Presentation  : Formats weather data in readable format
-   Visual Feedback  : Shows cache status and error messages
-   Responsive Design  : Works on desktop and mobile devices
-   Accessibility  : Includes proper semantic HTML and ARIA labels

  Key Components  :
-   Search Form  : Address input with validation
-   Current Weather  : Large temperature display with wind speed
-   3-Day Forecast  : Card-based layout with detailed information
-   Cache Indicator  : Shows whether data is cached or live
-   Error Messages  : User-friendly error display

---

## Design Patterns

The application implements several important design patterns that promote maintainability, scalability, and clean code architecture:

### 1. Service Object Pattern

  Implementation  : `WeatherService` class

  Purpose  : Encapsulates complex business logic for weather data retrieval.

  Benefits  :
-   Single Responsibility  : Handles only weather-related operations
-   Reusability  : Can be used in controllers, workers, or other services
-   Testability  : Easy to unit test in isolation
-   Maintainability  : Changes to weather logic are centralized

  Code Example  :
```ruby
class WeatherService
  def initialize(address)
    @address = address
  end

  def fetch_forecast
    geocode = geocode_address
    return {} if geocode.empty?
    
    # Complex weather data processing...
  end

  private

  def geocode_address
    # Geocoding logic...
  end
end
```

  Usage  :
```ruby
# In controller
service = WeatherService.new("New York, NY")
forecast = service.fetch_forecast

# In worker
service = WeatherService.new(address)
forecast = service.fetch_forecast
```

---

### 2. Repository Pattern

  Implementation  : `WeatherSearch` model with class methods

  Purpose  : Abstracts data access and provides a clean interface for database operations.

  Benefits  :
-   Data Access Abstraction  : Hides database complexity
-   Query Encapsulation  : Complex queries are encapsulated in methods
-   Consistency  : Standardized way to access data
-   Testability  : Easy to mock for testing

  Code Example  :
```ruby
class WeatherSearch < ApplicationRecord
  # Repository methods
  def self.log_search(address, postal_code = nil)
    # Complex data access logic
    search_record = find_or_initialize_by(
      address: normalized_address,
      postal_code: postal_code
    )
    # ... persistence logic
  end

  def self.popular_searches(limit = 3)
    select('address, postal_code, count')
      .order('count DESC')
      .limit(limit)
  end
end
```

  Usage  :
```ruby
# Log a search
WeatherSearch.log_search("London, UK", "SW1A 1AA")

# Get popular searches
popular = WeatherSearch.popular_searches(5)
```

---

### 3. Strategy Pattern

  Implementation  : Cache key generation strategy

  Purpose  : Allows different cache key strategies based on available data.

  Benefits  :
-   Flexibility  : Can switch between different caching strategies
-   Extensibility  : Easy to add new cache key strategies
-   Maintainability  : Each strategy is isolated

  Code Example  :
```ruby
class ForecastsController < ApplicationController
  private

  def fetch_weather_data(address)
    # Strategy 1: Postal code-based cache (preferred)
    service = WeatherService.new(address)
    geocode_result = service.geocode_address
    
    if geocode_result && geocode_result[:postal_code].present?
      postal_cache_key = "weather:postal:#{geocode_result[:postal_code]}"
      if Rails.cache.exist?(postal_cache_key)
        return Rails.cache.read(postal_cache_key)
      end
    end
    
    # Strategy 2: Address-based cache (fallback)
    address_cache_key = "weather:addr:#{address.parameterize}"
    if Rails.cache.exist?(address_cache_key)
      return Rails.cache.read(address_cache_key)
    end
    
    # Fetch fresh data and cache with both keys
    forecast = service.fetch_forecast
    
    # Cache with postal code first (preferred)
    if forecast[:postal_code].present?
      postal_cache_key = "weather:postal:#{forecast[:postal_code]}"
      Rails.cache.write(postal_cache_key, forecast, expires_in: 30.minutes)
    end
    
    # Also cache with address key
    Rails.cache.write(address_cache_key, forecast, expires_in: 30.minutes)
    
    forecast
  end
end
```

---

### 4. Template Method Pattern

  Implementation  : Controller action workflow

  Purpose  : Defines the skeleton of an algorithm while allowing subclasses to override specific steps.

  Benefits  :
-   Code Reuse  : Common workflow steps are shared
-   Consistency  : Ensures consistent processing flow
-   Flexibility  : Specific steps can be customized

  Code Example  :
```ruby
class ForecastsController < ApplicationController
  def show
    # Template method defines the workflow
    address = params[:address].to_s.strip
    
    # Step 1: Validate input
    unless valid_address?(address)
      flash[:alert] = I18n.t('weather.errors.invalid_address')
      redirect_to root_path and return
    end

    # Step 2: Fetch data
    @forecast = fetch_weather_data(address)
    
    # Step 3: Handle empty results
    if @forecast.empty?
      flash[:alert] = I18n.t('weather.errors.no_data')
      redirect_to root_path and return
    end

    # Step 4: Log search
    WeatherSearch.log_search(address, @forecast[:postal_code])
    
    # Step 5: Render results
    render :show
  end

  private

  # Hook methods that can be overridden
  def valid_address?(address)
    address.present? && address.length > 2
  end

  def fetch_weather_data(address)
    # Complex data fetching logic...
  end
end
```

---

### 5. Observer Pattern

  Implementation  : ActiveRecord callbacks in `WeatherSearch`

  Purpose  : Allows objects to be notified of changes in other objects.

  Benefits  :
-   Loose Coupling  : Objects don't need to know about each other
-   Automatic Updates  : Changes trigger automatic responses
-   Extensibility  : Easy to add new observers

  Code Example  :
```ruby
class WeatherSearch < ApplicationRecord
  # Observer callbacks
  before_validation :set_searched_at, on: :create
  before_save :normalize_address

  private

  # Observer methods
  def set_searched_at
    self.searched_at ||= Time.current
  end

  def normalize_address
    self.address = address.strip.titleize if address.present?
  end
end
```

  Benefits  :
-   Automatic Data Processing  : Address normalization happens automatically
-   Consistent Data  : Timestamps are set consistently
-   Separation of Concerns  : Data processing is separate from business logic

---

### 6. Command Pattern

  Implementation  : Sidekiq worker jobs

  Purpose  : Encapsulates requests as objects, allowing for queuing, logging, and undo operations.

  Benefits  :
-   Decoupling  : Invoker and receiver are decoupled
-   Queuing  : Commands can be queued for later execution
-   Logging  : Commands can be logged and audited
-   Undo Operations  : Commands can potentially be undone

  Code Example  :
```ruby
class ForecastRefresherWorker
  include Sidekiq::Worker
  sidekiq_options retry: 3, queue: :default

  # Command execution
  def perform
    # Encapsulated command logic
    current_hour = Time.zone.now.hour
    return unless current_hour.between?(6, 21)

    popular_searches = WeatherSearch.popular_searches(3)
    # ... command execution logic
  end
end
```

  Usage  :
```ruby
# Queue the command
ForecastRefresherWorker.perform_async

# Schedule the command
ForecastRefresherWorker.perform_in(30.minutes)
```

---

### 7. Facade Pattern

  Implementation  : Controller as facade for complex operations

  Purpose  : Provides a simplified interface to a complex subsystem including geocoding, caching with postal code priority, and weather data retrieval.

  Benefits  :
-   Simplification  : Hides complexity of underlying operations
-   Ease of Use  : Provides simple interface for complex operations
-   Maintainability  : Changes to subsystem don't affect clients

  Code Example  :
```ruby
class ForecastsController < ApplicationController
  def show
    # Facade method that orchestrates complex operations
    address = params[:address].to_s.strip
    
    # Complex workflow hidden behind simple interface
    @forecast = fetch_weather_data(address)
    WeatherSearch.log_search(address, @forecast[:postal_code])
    
    render :show
  end

  private

  def fetch_weather_data(address)
    # Complex subsystem orchestration
    # 1. Check postal code cache first (preferred)
    # 2. Check address cache as fallback
    # 3. Call external APIs if not cached
    # 4. Transform data
    # 5. Update cache with both postal code and address keys
    # All hidden behind simple method call
  end
end
```

---

### 8. Singleton Pattern

  Implementation  : Rails cache and logger instances

  Purpose  : Ensures a class has only one instance and provides global access to it.

  Benefits  :
-   Single Instance  : Ensures only one instance exists
-   Global Access  : Provides global access point
-   Resource Management  : Efficient resource usage

  Code Example  :
```ruby
# Rails cache singleton
Rails.cache.write('key', 'value')
cached_value = Rails.cache.read('key')

# Rails logger singleton
Rails.logger.info "Weather data fetched"
Rails.logger.error "API request failed"
```

---

### 9. Factory Pattern

  Implementation  : Service object instantiation

  Purpose  : Creates objects without specifying their exact class.

  Benefits  :
-   Flexibility  : Can create different types of objects
-   Encapsulation  : Creation logic is encapsulated
-   Extensibility  : Easy to add new object types

  Code Example  :
```ruby
# Factory method for creating services
def create_weather_service(address)
  WeatherService.new(address)
end

# Usage
service = create_weather_service("London, UK")
forecast = service.fetch_forecast
```

---

### 10. Decorator Pattern

  Implementation  : View helpers and data transformation

  Purpose  : Adds behavior to objects dynamically without altering their structure.

  Benefits  :
-   Flexibility  : Can add features dynamically
-   Composition  : Can combine multiple decorators
-   Single Responsibility  : Each decorator has one responsibility

  Code Example  :
```ruby
# Data transformation (decorator-like behavior)
def format_weather_data(raw_data)
  {
    address: raw_data[:address],
    postal_code: raw_data[:postal_code],
    current: {
      temperature: "#{raw_data[:current][:temperature]}°C",
      windspeed: "#{raw_data[:current][:windspeed]} km/h"
    },
    forecast: raw_data[:forecast].map do |day|
      {
        date: Date.parse(day[:date]).strftime('%A'),
        high: "#{day[:high]}°",
        low: "#{day[:low]}°"
      }
    end
  }
end
```

---

## Design Pattern Benefits Summary

| Pattern | Implementation | Benefits |
|---------|---------------|----------|
|   Service Object   | `WeatherService` | Encapsulates complex business logic |
|   Repository   | `WeatherSearch` methods | Abstracts data access |
|   Strategy   | Cache key generation | Flexible caching strategies |
|   Template Method   | Controller workflow | Consistent processing flow |
|   Observer   | ActiveRecord callbacks | Automatic data processing |
|   Command   | Sidekiq workers | Decoupled background processing |
|   Facade   | Controller interface | Simplified complex operations |
|   Singleton   | Rails cache/logger | Global resource access |
|   Factory   | Service instantiation | Flexible object creation |
|   Decorator   | Data transformation | Dynamic behavior addition |

These design patterns work together to create a maintainable, scalable, and well-structured application that follows SOLID principles and Rails best practices.

---

## API Integration

### External APIs Used

1.   Geoapify Geocoding API   (Primary)
   -   Purpose  : Geocoding (address → coordinates + postal code)
   -   Endpoint  : `https://api.geoapify.com/v1/geocode/search`
   -   Rate Limit  : 3,000 requests/day (free tier)
   -   Cost  : Free with API key
   -   Response Format  : JSON with detailed location data
   -   Benefits  : Excellent postal code coverage, high accuracy

2.   OpenStreetMap Nominatim API   (Fallback)
   -   Purpose  : Geocoding fallback (address → coordinates)
   -   Endpoint  : `https://nominatim.openstreetmap.org/search`
   -   Rate Limit  : 1 request per second
   -   Cost  : Completely free
   -   Response Format  : JSON array of location results
   -   Benefits  : Always works, no API key required

3.   Open-Meteo API  
   -   Purpose  : Weather data retrieval
   -   Endpoint  : `https://api.open-meteo.com/v1/forecast`
   -   Rate Limit  : 10,000 requests per day
   -   Cost  : Free
   -   Response Format  : JSON with current and daily forecast data

### API Data Flow

```
User Input: "London, UK"
  ↓
1. Geoapify API (Primary)
   - Geocoding: "London, UK" → {lat: 51.5074, lon: -0.1278, postal_code: "SW1A 1AA"}
   - If fails → Nominatim API (Fallback)
  ↓
2. Open-Meteo API
   - Weather: {lat: 51.5074, lon: -0.1278} → {current: {...}, forecast: [...]}
  ↓
3. Caching (Postal Code Priority)
   - Primary Key: "weather:postal:SW1A 1AA"
   - Fallback Key: "weather:addr:london-uk"
  ↓
4. Response
   - Weather data + cache status + search logging
```

## Features

### Core Features

-   Weather Search  : Search by any address worldwide
-   Advanced Geocoding  : Multiple geocoding APIs with postal code extraction
-   Current Conditions  : Real-time temperature and wind speed
-   3-Day Forecast  : Detailed daily forecasts with temperature ranges
-   Postal Code Priority Caching  : Maximum cache efficiency with postal code-based keys
-   Search Analytics  : Tracks popular locations for optimization
-   Background Refresh  : Automated cache updates for popular locations
-   Environment Configuration  : Secure API key management

### Technical Features

-   Error Handling  : Graceful API failure management
-   Input Validation  : Address format validation
-   Internationalization  : Multi-language error messages
-   Responsive Design  : Mobile-friendly interface
-   Performance Optimization  : Cache-first strategy
-   Background Processing  : Sidekiq job processing

## Installation

### Prerequisites

- Ruby 2.7.3+
- Rails 5.0.1
- SQLite3
- Sidekiq (for background jobs)

### Setup

1.   Clone the repository  
   ```bash
   git clone <repository-url>
   cd nihitha-weather-forecast
   ```

2.   Install dependencies  
   ```bash
   bundle install
   ```

3.   Set up API keys   (Required for optimal geocoding)
   ```bash
   # Set Geoapify API key (recommended)
   export GEOAPIFY_API_KEY="your_geoapify_api_key_here"
   ```

4.   Setup database  
   ```bash
   rails db:create
   rails db:migrate
   ```

4.   Start the application  
   ```bash
   rails server
   ```

5.   Start Sidekiq (for background jobs)  
   ```bash
   bundle exec sidekiq
   ```

## Usage

### Web Interface

1.   Search for Weather  
   - Navigate to `http://localhost:4000`
   - Enter an address (e.g., "New York, NY")
   - Click "Get Forecast"

2.   View Results  
   - Current temperature and wind speed
   - 3-day forecast with detailed information
   - Cache status indicator

### API Usage

The application can be used programmatically:

```ruby
# Get weather data
service = WeatherService.new("London, UK")
forecast = service.fetch_forecast

# Log a search
WeatherSearch.log_search("Paris, France", "75001")

# Get popular searches
popular = WeatherSearch.popular_searches(5)

# Refresh popular locations
ForecastRefresherWorker.perform_async
```

## Testing

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test suites
bundle exec rspec spec/models/
bundle exec rspec spec/services/
bundle exec rspec spec/controllers/
bundle exec rspec spec/workers/
```

### Test Coverage

-   Models  : 18 tests covering validations, callbacks, and class methods
-   Services  : 11 tests covering API integration and error handling
-   Controllers  : 9 tests covering request handling and caching
-   Workers  : 6 tests covering background job processing

### Test Categories

1.   Unit Tests  : Individual component testing
2.   Integration Tests  : API integration testing
3.   Controller Tests  : Request/response testing
4.   Worker Tests  : Background job testing

## Configuration

### Environment Variables

#### Required API Keys

```bash
# Geoapify API Key (Primary geocoding service)
export GEOAPIFY_API_KEY="your_geoapify_api_key_here"
```
#### Getting API Keys

1.   Geoapify API   (Recommended):
   - Go to [geoapify.com](https://www.geoapify.com/)
   - Sign up for free account
   - Get API key from dashboard
   - Free tier: 3,000 requests/day


#### Cache Key Strategy

The application uses a   postal code priority   caching strategy:

1.   Primary Cache Key  : `weather:postal:{postal_code}` (e.g., `weather:postal:SW1A 1AA`)
2.   Fallback Cache Key  : `weather:addr:{address}` (e.g., `weather:addr:london-uk`)

  Benefits  :
-   Maximum Cache Hits  : Postal codes provide broader cache coverage
-   Efficiency  : One cached result serves multiple address variations
-   Performance  : Reduces API calls significantly

  Cache Flow  :
```
1. Check postal code cache first
2. If miss, check address cache
3. If miss, fetch from API
4. Cache with both postal code and address keys
```

### Sidekiq Configuration

```yaml
# config/sidekiq.yml
:concurrency: 5
:queues:
  - default
```

### Database Configuration

```yaml
# config/database.yml
development:
  adapter: sqlite3
  database: db/development.sqlite3

test:
  adapter: sqlite3
  database: db/test.sqlite3
```

## Performance Considerations

### Caching Strategy

-   Cache Keys  : Postal code-based keys for optimal efficiency
-   Cache Duration  : 30-minute TTL for weather data
-   Cache Fallback  : Address-based keys when postal code unavailable

### API Optimization

-   Rate Limiting  : Respects API rate limits
-   Error Handling  : Graceful degradation on API failures
-   Background Refresh  : Reduces API calls for popular locations

### Database Optimization

-   Indexes  : Optimized queries for popular searches
-   Data Normalization  : Consistent address formatting
-   Search Analytics  : Efficient counting and grouping

---

## Conclusion

This weather forecast application demonstrates a well-structured Rails application with clear object decomposition, comprehensive error handling, and intelligent caching strategies. The modular architecture allows for easy maintenance and future enhancements while providing excellent performance and user experience.