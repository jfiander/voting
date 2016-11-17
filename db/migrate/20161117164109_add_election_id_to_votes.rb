class AddElectionIdToVotes < ActiveRecord::Migration[5.0]
  def change
    add_column :votes, :election_id, :integer
  end
end
