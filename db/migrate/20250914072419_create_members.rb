class CreateMembers < ActiveRecord::Migration[7.2]
  def change
    create_table :members do |t|
      t.string  :name,        null: false
      t.integer :grade,       null: false
      t.integer :skill_level, null: false, default: 0
      t.integer :gender,      null: false, default: 0
      t.boolean :active,      null: false, default: true
      t.timestamps
    end
    add_index :members, :active
    add_index :members, :gender
    add_index :members, :skill_level
  end
end
