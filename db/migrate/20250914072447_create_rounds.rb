class CreateRounds < ActiveRecord::Migration[7.2]
  def change
    create_table :rounds do |t|
      t.references :event, null: false, foreign_key: true
      t.integer :index,    null: false
      t.integer :status,   null: false, default: 0
      t.timestamps
    end
    add_index :rounds, [:event_id, :index], unique: true
  end
end
