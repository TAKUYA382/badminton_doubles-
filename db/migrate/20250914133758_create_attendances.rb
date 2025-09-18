# db/migrate/XXXXXXXXXXXXXX_create_attendances.rb
class CreateAttendances < ActiveRecord::Migration[7.1]
  def change
    create_table :attendances do |t|
      t.references :event,  null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.integer :status,    null: false, default: 0   # 0:未定, 1:参加, 2:不参加
      t.text :note

      t.timestamps
    end

    add_index :attendances, [:event_id, :member_id], unique: true
    add_index :attendances, :status
  end
end
