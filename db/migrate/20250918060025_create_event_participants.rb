# db/migrate/20240918000000_create_event_participants.rb
class CreateEventParticipants < ActiveRecord::Migration[7.2]
  def change
    create_table :event_participants do |t|
      t.references :event,  null: false, foreign_key: true
      t.references :member, null: false, foreign_key: true
      t.integer :status, null: false, default: 1  # 1:参加、0:未定、-1:欠席
      t.timestamps
    end
    add_index :event_participants, [:event_id, :member_id], unique: true
  end
end