# app/models/member_relation.rb
class MemberRelation < ApplicationRecord
  # ================================
  # 種別定義
  # ================================
  enum kind: { avoid_pair: 0, avoid_opponent: 1 }  # 0: ペアNG, 1: 対戦NG

  # ================================
  # 関連
  # ================================
  belongs_to :member,       class_name: "Member"
  belongs_to :other_member, class_name: "Member"

  # ================================
  # バリデーション
  # ================================
  validate :different_members
  validates :kind, presence: true

  # 同じ組み合わせ・同じ種別は重複登録不可（正規化後の順序でユニーク）
  validates :member_id, uniqueness: { scope: [:other_member_id, :kind] }

  # (A,B) と (B,A) を同一視するため、保存前に常に小さいIDを左に寄せる
  before_validation :normalize_order

  # ================================
  # スコープ
  # ================================
  scope :between, ->(a, b) do
    ids = [a.id, b.id].sort
    where(member_id: ids[0], other_member_id: ids[1])
  end

  # ================================
  # クラスメソッド
  # ================================
  # 2人の間に指定種別のNGがあるかを判定
  #
  # 使用例:
  #   MemberRelation.ng_between?(m1.id, m2.id, "avoid_pair")
  #   MemberRelation.ng_between?(m1.id, m2.id, "avoid_opponent")
  #
  # 戻り値:
  #   true  → NGあり
  #   false → NGなし
  # ================================
  def self.ng_between?(a_id, b_id, kind)
    return false if a_id.blank? || b_id.blank? || a_id == b_id

    x, y = [a_id.to_i, b_id.to_i].sort
    where(member_id: x, other_member_id: y, kind: kind).exists?
  end

  private

  # 同一メンバー同士の設定は禁止
  def different_members
    if member_id == other_member_id
      errors.add(:base, "同一メンバー同士は指定できません")
    end
  end

  # IDの小さい方をmember_id、大きい方をother_member_idにして正規化
  def normalize_order
    return if member_id.blank? || other_member_id.blank?
    a, b = [member_id, other_member_id].sort
    self.member_id       = a
    self.other_member_id = b
  end
end