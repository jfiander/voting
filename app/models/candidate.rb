class Candidate < ApplicationRecord
  belongs_to :party, optional: true

  def party
    Party.get(self.party_id)
  end
end
