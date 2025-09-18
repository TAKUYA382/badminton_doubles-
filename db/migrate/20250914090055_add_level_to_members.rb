# db/migrate/XXXXXXXXXX_add_level_to_members.rb
class AddLevelToMembers < ActiveRecord::Migration[7.1]
  def change
    add_column :members, :level, :integer, null: false, default: 0
    add_index  :members, :level
  end
end
