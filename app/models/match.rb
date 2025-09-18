class Match < ApplicationRecord
  belongs_to :round
  belongs_to :pair1_member1, class_name: "Member", optional: true
  belongs_to :pair1_member2, class_name: "Member", optional: true
  belongs_to :pair2_member1, class_name: "Member", optional: true
  belongs_to :pair2_member2, class_name: "Member", optional: true

  # ===============================
  # バリデーション
  # ===============================
  validates :court_number, presence: true
  validate :members_are_all_distinct
  validate :check_member_relations

  # ===============================
  # 4スロット全てを配列で返す
  # ===============================
  def members
    [pair1_member1, pair1_member2, pair2_member1, pair2_member2].compact
  end

  # ===============================
  # スロットのキー名（UIで使う用）
  # ===============================
  def slot_keys
    %w[pair1_member1 pair1_member2 pair2_member1 pair2_member2]
  end

  # ===============================
  # 指定したスロットを空にする
  # ===============================
  def clear_slot!(slot_key)
    ensure_valid_slot!(slot_key)
    update!("#{slot_key}_id" => nil) # *_id で更新
  end

  # ===============================
  # 指定したスロットにメンバーを差し替える
  # ===============================
  def replace_member!(slot_key, member_id)
    ensure_valid_slot!(slot_key)
    mid = member_id.presence&.to_i
    raise ActiveRecord::RecordInvalid.new(self), "メンバーが選択されていません" if mid.blank?

    # *_id に整数で代入（関連名に直接整数を入れない）
    update!("#{slot_key}_id" => mid)
  end

  # ===============================
  # この試合で特定のメンバーが含まれているか確認
  # ===============================
  def includes_member?(member)
    members.any? { |m| m.id == member.id }
  end

  private

  # ===============================
  # スロット名の正当性チェック
  # ===============================
  def ensure_valid_slot!(slot_key)
    unless slot_keys.include?(slot_key.to_s)
      raise ArgumentError, "不正なスロット名です: #{slot_key}"
    end
  end

  # ===============================
  # バリデーション①
  # 同じメンバーを重複して割り当て禁止
  # ===============================
  def members_are_all_distinct
    ids = members.map(&:id)
    if ids.uniq.size != ids.size
      errors.add(:base, "同じメンバーを同一試合に重複して割り当てられません")
    end
  end

  # ===============================
  # バリデーション②
  # ペアNG / 対戦NGチェック
  # ===============================
  def check_member_relations
    return if members.size < 2

    pair1 = [pair1_member1, pair1_member2].compact
    pair2 = [pair2_member1, pair2_member2].compact

    # ---------- ペアNGチェック ----------
    pair1.combination(2).each do |m1, m2|
      if MemberRelation.ng_between?(m1.id, m2.id, "avoid_pair")
        errors.add(:base, "#{m1.name} と #{m2.name} はペアNGです")
      end
    end
    pair2.combination(2).each do |m1, m2|
      if MemberRelation.ng_between?(m1.id, m2.id, "avoid_pair")
        errors.add(:base, "#{m1.name} と #{m2.name} はペアNGです")
      end
    end

    # ---------- 対戦NGチェック ----------
    pair1.each do |m1|
      pair2.each do |m2|
        if MemberRelation.ng_between?(m1.id, m2.id, "avoid_opponent")
          errors.add(:base, "#{m1.name} と #{m2.name} は対戦NGです")
        end
      end
    end
  end
end