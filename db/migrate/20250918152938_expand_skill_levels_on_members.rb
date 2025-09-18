# db/migrate/20250919000100_expand_skill_levels_on_members.rb
class ExpandSkillLevelsOnMembers < ActiveRecord::Migration[7.2]
  def up
    # skill_level カラムを安全な状態に変更（整数型、NOT NULL、デフォルトはC=3）
    change_column :members, :skill_level, :integer, null: false, default: 3

    # 旧値 → 新値 の対応
    # 既存: { beginner:0, middle:1, advanced:2 }
    # 新しい11段階: 
    #   A_plus(10) > A(9) > A_minus(8) > B_plus(7) > B(6) > B_minus(5) >
    #   C_plus(4) > C(3) > C_minus(2) > D_plus(1) > D(0)
    #
    # 旧値をざっくり A/B/C の中心へマッピング
    execute <<~SQL
      UPDATE members SET skill_level = 9 WHERE skill_level = 2; -- advanced → A(9)
      UPDATE members SET skill_level = 6 WHERE skill_level = 1; -- middle   → B(6)
      UPDATE members SET skill_level = 3 WHERE skill_level = 0; -- beginner → C(3)
    SQL
  end

  def down
    # 巻き戻し時はA系→advanced、B系→middle、C/D系→beginnerに戻す
    execute <<~SQL
      UPDATE members SET skill_level = 2 WHERE skill_level IN (8,9,10); -- A-,A,A+
      UPDATE members SET skill_level = 1 WHERE skill_level IN (5,6,7);  -- B-,B,B+
      UPDATE members SET skill_level = 0 WHERE skill_level IN (0,1,2,3,4); -- C-,C,C+,D+,D
    SQL

    change_column :members, :skill_level, :integer, null: false, default: 0
  end
end