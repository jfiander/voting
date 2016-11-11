class CreateVotes < ActiveRecord::Migration[5.0]
  def change
    create_table :votes do |t|
      t.string :preferences_hash

      t.timestamps
    end
  end
end
