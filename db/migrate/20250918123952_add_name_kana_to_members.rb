# db/migrate/20250919000000_add_name_kana_to_members.rb
class AddNameKanaToMembers < ActiveRecord::Migration[7.2]
  def change
    add_column :members, :name_kana, :string, null: false, default: ""
    add_index  :members, :name_kana
  end
end