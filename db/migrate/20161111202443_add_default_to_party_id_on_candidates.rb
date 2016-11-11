class AddDefaultToPartyIdOnCandidates < ActiveRecord::Migration[5.0]
  def change
    change_column :candidates, :party_id, :integer, default: 1
  end
end
