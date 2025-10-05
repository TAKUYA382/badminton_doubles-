class AddArrivalLeaveToEventParticipants < ActiveRecord::Migration[7.2]
  def change
    # 到着・退出ラウンド（1始まり）。nil は「制限なし」を意味
    add_column :event_participants, :arrival_round, :integer, null: true
    add_column :event_participants, :leave_round,   :integer, null: true

    # 参加ステータスの拡張: attending(既存), late, early_leave, absent
    # 既存statusカラム(enum整数)をそのまま使う前提。未使用なら新規追加してOK。
    # 既存データは attending として扱い、到着=1/退出=nil に初期化
    reversible do |dir|
      dir.up do
        execute <<~SQL
          UPDATE event_participants
          SET arrival_round = 1
          WHERE arrival_round IS NULL;
        SQL
      end
    end
  end
end