class CreateMatches < ActiveRecord::Migration[7.2]
  def change
    create_table :matches do |t|
      t.references :round, null: false, foreign_key: true
      t.integer :court_number, null: false
      t.references :pair1_member1, null: false, foreign_key: { to_table: :members }
      t.references :pair1_member2, null: false, foreign_key: { to_table: :members }
      t.references :pair2_member1, null: false, foreign_key: { to_table: :members }
      t.references :pair2_member2, null: false, foreign_key: { to_table: :members }
      t.timestamps
    end
    add_index :matches, [:round_id, :court_number], unique: true
  end
end
