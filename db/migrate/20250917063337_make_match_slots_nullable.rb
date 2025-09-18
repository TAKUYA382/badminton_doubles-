# db/migrate/XXXXXXXXXXXXXX_make_match_slots_nullable.rb
class MakeMatchSlotsNullable < ActiveRecord::Migration[7.2]
  def change
    change_column_null :matches, :pair1_member1_id, true
    change_column_null :matches, :pair1_member2_id, true
    change_column_null :matches, :pair2_member1_id, true
    change_column_null :matches, :pair2_member2_id, true
  end
end