class CreateElections < ActiveRecord::Migration[5.0]
  def change
    create_table :elections do |t|
      t.string :description
      t.datetime :date

      t.timestamps
    end
  end
end
