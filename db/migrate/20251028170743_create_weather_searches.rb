class CreateWeatherSearches < ActiveRecord::Migration[5.0]
  def change
    create_table :weather_searches do |t|
      t.string :address
      t.string :postal_code
      t.integer :count
      t.datetime :searched_at
    end
  end
end
