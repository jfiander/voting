class Election < ApplicationRecord
  has_many :votes

  before_create do
    self.description = "Test Election #{SecureRandom.hex(12)}" if self.description.blank?
    self.date = Time.now + 2.months if self.date.blank?
  end
end
