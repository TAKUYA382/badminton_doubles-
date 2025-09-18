# app/models/member.rb
class Member < ApplicationRecord
  # === 出欠管理（旧機能：Attendance） ===
  has_many :attendances, dependent: :destroy
  has_many :events, through: :attendances

  # === 参加者管理（新機能：EventParticipant） ===
  has_many :event_participants, dependent: :destroy
  has_many :participated_events, through: :event_participants, source: :event

  # === enum（A+ が最強 / D が最弱。数値が大きいほど強い） ===
  enum skill_level: {
    D:        0,
    D_plus:   1,
    C_minus:  2,
    C:        3,
    C_plus:   4,
    B_minus:  5,
    B:        6,
    B_plus:   7,
    A_minus:  8,
    A:        9,
    A_plus:   10
  }
  enum gender: { male: 0, female: 1 }

  # === スコープ ===
  scope :active, -> { where(active: true) }

  # 名前/読み（かな）を部分一致検索（% と _ を LIKE エスケープ）
  scope :name_like, ->(q) {
    next all if q.blank?
    esc = q.to_s.gsub(/[\\%_]/) { |m| "\\#{m}" }
    t = arel_table
    cond = t[:name].matches("%#{esc}%").or(t[:name_kana].matches("%#{esc}%"))
    where(cond)
  }

  # 指定イベントで「参加(attending)」のメンバーだけ
  scope :attending_for_event, ->(event) {
    joins(:event_participants)
      .where(event_participants: { event_id: event.id, status: EventParticipant.statuses[:attending] })
  }

  # 読み順（name_kana → 無ければ name）で並べ替え
  scope :order_by_reading, -> {
    order(Arel.sql("COALESCE(NULLIF(name_kana, ''), name) ASC"))
  }

  # === 学年 ===
  GRADE_OPTIONS = [
    ["1年", 1], ["2年", 2], ["3年", 3], ["4年", 4],
    ["M1", 5], ["M2", 6]
  ].freeze

  GRADE_LABELS = {
    1 => "1年", 2 => "2年", 3 => "3年", 4 => "4年",
    5 => "M1", 6 => "M2"
  }.freeze

  # === バリデーション ===
  validates :name, :skill_level, :gender, presence: true
  validates :grade, presence: true, inclusion: { in: 1..6 }
  # 読み（かな）は任意。ひらがな/カタカナ/長音/中黒/空白のみ許可
  validates :name_kana,
            format: { with: /\A[ぁ-んァ-ヶー・\s　]*\z/, message: "はひらがな/カタカナで入力してください" },
            allow_blank: true

  # === 対人NG設定 ===
  has_many :member_relations_as_a, class_name: "MemberRelation", foreign_key: :member_id, dependent: :destroy
  has_many :member_relations_as_b, class_name: "MemberRelation", foreign_key: :other_member_id, dependent: :destroy

  # === コールバック（読みの正規化）===
  before_validation :normalize_name_kana

  # === 便利メソッド（NG関係判定）===
  def blocked_pair_with?(other)
    MemberRelation.avoid_pair.between(self, other).exists?
  end

  def blocked_opponent_with?(other)
    MemberRelation.avoid_opponent.between(self, other).exists?
  end

  # === 表示用ラベル ===
  def skill_label
    # locales 例:
    # ja:
    #   enums:
    #     member:
    #       skill_level:
    #         A_plus: "A+"
    #         A: "A"
    #         A_minus: "A-"
    #         B_plus: "B+"
    #         B: "B"
    #         B_minus: "B-"
    #         C_plus: "C+"
    #         C: "C"
    #         C_minus: "C-"
    #         D_plus: "D+"
    #         D: "D"
    I18n.t("enums.member.skill_level.#{skill_level}")
  end

  def gender_label
    I18n.t("enums.member.gender.#{gender}")
  end

  def grade_label
    GRADE_LABELS[grade] || grade.to_s
  end

  # 強さ比較用の数値（大きいほど強い）
  def skill_value
    self.class.skill_levels[skill_level].to_i
  end

  # セレクト用の表示ラベル（読みは補助表示）
  def label_for_select
    kana = name_kana.present? ? " / #{name_kana}" : ""
    "#{name}#{kana}（#{grade_label}・#{gender_label}・#{skill_label}）"
  end

  private

  # ひらがな→カタカナ、空白正規化
  def normalize_name_kana
    return if name_kana.blank?
    s = name_kana.to_s
    s = s.tr("　", " ").strip      # 全角空白→半角、前後空白除去
    s = s.gsub(/\s+/, " ")         # 連続空白を1つに
    s = s.tr("ぁ-ゖ", "ァ-ヶ")     # ひらがな→カタカナ（保存はカナに寄せる）
    self.name_kana = s
  end
end