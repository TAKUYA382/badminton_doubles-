class AddIndexToMembersName < ActiveRecord::Migration[7.1]
  def change
    add_index :members, :name
  end
end
