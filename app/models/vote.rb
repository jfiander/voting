class Vote < ApplicationRecord
  belongs_to :election

  validates :preferences_hash, presence: true

  def preferences
    hash = JSON.parse(self.preferences_hash.gsub('=>', ':')).map do |preference, candidate_id|
      {preference.to_i => candidate_id.to_i}
    end

    hash.reduce({}, :merge)
  end

  def self.format_preferences(hash)
    "{#{hash.map { |preference, candidate| "\"#{preference}\"=>\"#{candidate}\""}.join(",")}}"
  end
end
