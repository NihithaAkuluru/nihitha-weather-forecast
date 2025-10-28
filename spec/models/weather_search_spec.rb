require 'rails_helper'

RSpec.describe WeatherSearch, type: :model do
  describe 'validations' do
    it 'is valid with valid attributes' do
      weather_search = WeatherSearch.new(
        address: "New York, NY",
        postal_code: "10001",
        count: 5,
        searched_at: Time.current
      )
      expect(weather_search).to be_valid
    end

    it 'requires address to be present' do
      weather_search = WeatherSearch.new(address: nil)
      expect(weather_search).not_to be_valid
      expect(weather_search.errors[:address]).to include("can't be blank")
    end

    it 'requires address to be at least 2 characters' do
      weather_search = WeatherSearch.new(address: "N")
      expect(weather_search).not_to be_valid
      expect(weather_search.errors[:address]).to include("is too short (minimum is 2 characters)")
    end

    it 'requires address to be at most 255 characters' do
      weather_search = WeatherSearch.new(address: "A" * 256)
      expect(weather_search).not_to be_valid
      expect(weather_search.errors[:address]).to include("is too long (maximum is 255 characters)")
    end

    it 'requires postal_code to be at most 20 characters' do
      weather_search = WeatherSearch.new(postal_code: "A" * 21)
      expect(weather_search).not_to be_valid
      expect(weather_search.errors[:postal_code]).to include("is too long (maximum is 20 characters)")
    end

    it 'requires count to be present' do
      weather_search = WeatherSearch.new(count: nil)
      expect(weather_search).not_to be_valid
      expect(weather_search.errors[:count]).to include("can't be blank")
    end

    it 'requires count to be an integer' do
      weather_search = WeatherSearch.new(count: "not_a_number")
      expect(weather_search).not_to be_valid
      expect(weather_search.errors[:count]).to include("is not a number")
    end

    it 'requires count to be greater than or equal to 0' do
      weather_search = WeatherSearch.new(count: -1)
      expect(weather_search).not_to be_valid
      expect(weather_search.errors[:count]).to include("must be greater than or equal to 0")
    end

    it 'sets searched_at automatically via callback' do
      weather_search = WeatherSearch.new(address: "New York, NY", count: 1)
      weather_search.valid?
      expect(weather_search.searched_at).to be_present
    end
  end

  describe 'callbacks' do
    it 'sets searched_at before validation on create' do
      weather_search = WeatherSearch.new(address: "New York, NY", count: 1)
      weather_search.valid?
      expect(weather_search.searched_at).to be_present
    end

    it 'normalizes address before save' do
      weather_search = WeatherSearch.create!(
        address: "  new york, ny  ",
        count: 1,
        searched_at: Time.current
      )
      expect(weather_search.address).to eq("New York, Ny")
    end
  end

  describe 'class methods' do
    describe '.log_search' do
      it 'creates a new weather search record' do
        expect {
          WeatherSearch.log_search("New York, NY", "10001")
        }.to change(WeatherSearch, :count).by(1)
      end

      it 'returns the created record' do
        result = WeatherSearch.log_search("New York, NY", "10001")
        expect(result).to be_a(WeatherSearch)
        expect(result.address).to eq("New York, Ny") # titleize converts to this
        expect(result.postal_code).to eq("10001")
        expect(result.count).to eq(1)
      end

      it 'handles validation errors gracefully' do
        result = WeatherSearch.log_search("", "10001")
        expect(result).to be_nil
      end

      it 'normalizes the address before saving' do
        result = WeatherSearch.log_search("  new york, ny  ", "10001")
        expect(result).to be_a(WeatherSearch)
        expect(result.address).to eq("New York, Ny")
      end

      it 'sets searched_at automatically' do
        freeze_time = Time.zone.parse("2025-01-28 12:00:00")
        allow(Time).to receive(:current).and_return(freeze_time)
        
        result = WeatherSearch.log_search("New York, NY", "10001")
        expect(result.searched_at).to eq(freeze_time)
      end
    end

    describe '.popular_searches' do
      before do
        WeatherSearch.create!(address: "New York, NY", postal_code: "10001", count: 10, searched_at: Time.current)
        WeatherSearch.create!(address: "London, UK", postal_code: "SW1A 1AA", count: 8, searched_at: Time.current)
        WeatherSearch.create!(address: "Tokyo, Japan", postal_code: "100-0001", count: 5, searched_at: Time.current)
        WeatherSearch.create!(address: "Paris, France", postal_code: "75001", count: 3, searched_at: Time.current)
      end

      it 'returns top searches ordered by count' do
        popular = WeatherSearch.popular_searches(3)
        expect(popular.length).to eq(3)
        expect(popular.first.count).to eq(10)
        expect(popular.last.count).to eq(5)
      end

      it 'returns specified limit' do
        popular = WeatherSearch.popular_searches(2)
        expect(popular.length).to eq(2)
      end
    end
  end
end
