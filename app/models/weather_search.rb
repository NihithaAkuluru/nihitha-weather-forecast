class WeatherSearch < ApplicationRecord
  # Validations
  validates :address, presence: true, length: { minimum: 2, maximum: 255 }
  validates :postal_code, length: { maximum: 20 }, allow_blank: true
  validates :count, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Callbacks
  before_validation :set_searched_at, on: :create
  before_save :normalize_address

  # Class methods
  # Logs a weather search, incrementing count for existing searches
  #
  # Finds existing search record by address and postal code, or creates a new one.
  # Increments the count for existing searches to track popularity.
  #
  # @param address [String] The searched address
  # @param postal_code [String] The postal code (optional)
  # @return [WeatherSearch] The created or updated search record
  # @return [nil] If logging fails
  def self.log_search(address, postal_code = nil)
    # Normalize the address for consistent lookups
    normalized_address = address.strip.titleize
    
    # Find existing search or create new one
    search_record = find_or_initialize_by(
      address: normalized_address,
      postal_code: postal_code
    )
    
    if search_record.persisted?
      # Increment count for existing search
      search_record.increment!(:count)
      search_record.update!(searched_at: Time.current)
    else
      # Create new search record
      search_record.assign_attributes(
        count: 1,
        searched_at: Time.current
      )
      search_record.save!
    end
    
    search_record
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Failed to log weather search: #{e.message}"
    nil
  end

  def self.popular_searches(limit = 3)
    select('address, postal_code, count')
      .order('count DESC')
      .limit(limit)
  end


  private

  def set_searched_at
    self.searched_at ||= Time.current
  end

  def normalize_address
    self.address = address.strip.titleize if address.present?
  end
end
