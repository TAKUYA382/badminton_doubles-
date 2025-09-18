class CreateEvents < ActiveRecord::Migration[7.2]
  def change
    create_table :events do |t|
      t.string  :title,       null: false
      t.date    :date,        null: false
      t.integer :court_count, null: false, default: 2
      t.integer :status,      null: false, default: 0 # draft
      t.timestamps
    end
    add_index :events, :date
    add_index :events, :status
  end
end
