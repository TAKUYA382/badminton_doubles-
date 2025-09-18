class CreateMemberRelations < ActiveRecord::Migration[7.2]
  def change
    create_table :member_relations do |t|
      t.integer :member_id,       null: false
      t.integer :other_member_id, null: false
      t.integer :kind,            null: false, default: 0  # 0: ペアNG / 1: 対戦NG
      t.timestamps
    end

    # ================================
    # インデックス設定
    # ================================
    # 同じ2人 + 同じ種別 の組み合わせは1つまで（重複登録防止）
    add_index :member_relations,
              [:member_id, :other_member_id, :kind],
              unique: true,
              name: "idx_member_relations_unique"

    # 順序が逆でも同じ関係と見なす（(A,B) と (B,A) を同一視）
    add_index :member_relations,
              [:other_member_id, :member_id, :kind],
              unique: true,
              name: "idx_member_relations_unique_rev"

    # 検索効率化用
    add_index :member_relations, :member_id
    add_index :member_relations, :other_member_id
  end
end