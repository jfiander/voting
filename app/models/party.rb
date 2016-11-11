class Party < ApplicationRecord
  has_many :candidates

  def self.get(id)
    party = self.find_by(id: id)
    party.present? ? party : Party.find_by(name: "Independent")
  end
end
