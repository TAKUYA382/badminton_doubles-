# app/models/event_participant.rb
# frozen_string_literal: true

class EventParticipant < ApplicationRecord
  # ================================
  # アソシエーション
  # ================================
  belongs_to :event
  belongs_to :member

  # ================================
  # ステータス（参加の種類）
  # ================================
  # 参加:        全ラウンド or 指定範囲
  # 途中参加:    arrival_round 以降でのみ出場
  # 途中退出:    leave_round まで出場
  # 不参加:      一切出場しない
  # 未定:        編成に含めるかはスコープで制御
  enum status: {
    undecided:   0, # 未定
    attending:   1, # 参加
    late:        2, # 途中参加（到着ラウンドあり）
    early_leave: 3, # 途中退出（退出ラウンドあり）
    absent:      4  # 不参加
  }

  # ================================
  # バリデーション
  # ================================
  # 同じイベントに同じメンバーを重複登録させない
  validates :event_id, uniqueness: { scope: :member_id }

  # ラウンド指定は正の整数（1開始）／空なら無制限
  validates :arrival_round,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 },
            allow_nil: true
  validates :leave_round,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 },
            allow_nil: true

  validate :arrival_not_after_leave

  # ステータスと到着/退出の整合性を軽く補正
  before_validation :normalize_rounds_by_status

  # ================================
  # スコープ
  # ================================
  # 編成に含める候補（＝不参加は除外）
  scope :enrolled, -> {
    where(status: [statuses[:attending], statuses[:late], statuses[:early_leave], statuses[:undecided]])
  }

  # 特定ラウンドで出場可能な人（DBレベルで絞る）
  scope :available_on, ->(round_index) {
    where.not(status: statuses[:absent])
      .where("(arrival_round IS NULL OR arrival_round <= ?)", round_index)
      .where("(leave_round   IS NULL OR leave_round   >= ?)", round_index)
  }

  # ================================
  # ラベル系
  # ================================
  def status_label
    case status.to_sym
    when :attending   then "参加"
    when :late        then "途中参加"
    when :early_leave then "途中退出"
    when :absent      then "不参加"
    when :undecided   then "未定"
    else "-"
    end
  end

  # 一覧やログ用の短い表示
  def display_name
    base = "#{member.name}（#{status_label}）"
    ar   = arrival_round ? "到着#{arrival_round}R" : nil
    lr   = leave_round   ? "退出#{leave_round}R"   : nil
    tail = [ar, lr].compact.join(" / ")
    tail.present? ? "#{base} #{tail}" : base
  end

  # ================================
  # 編成用ユーティリティ
  # ================================
  # 指定ラウンドで出場できるか（アプリ内ロジック向け）
  def available_on_round?(round_index)
    return false if absent?
    return false if arrival_round.present? && round_index < arrival_round
    return false if leave_round.present?   && round_index > leave_round
    true
  end

  # 実効的な到着/退出ラウンド（nilは無制限扱い）
  def effective_arrival_round
    arrival_round.presence || 1
  end

  def effective_leave_round
    leave_round # nil は「上限なし」
  end

  private

  # 到着が退出を超えていないか
  def arrival_not_after_leave
    return if arrival_round.blank? || leave_round.blank?
    if arrival_round > leave_round
      errors.add(:arrival_round, "は退出ラウンドより後にできません")
      errors.add(:leave_round,   "は到着ラウンドより前にできません")
    end
  end

  # ステータスと round のゆるい整合性
  def normalize_rounds_by_status
    case status&.to_sym
    when :late
      # 途中参加なのに到着未指定ならデフォルト 2R 到着（任意）
      self.arrival_round ||= 2
      # 退出だけ入っていてもOK（途中参加＋早退）
    when :early_leave
      # 途中退出なのに退出未指定なら最低 1R（実質出場なし回避）
      self.leave_round ||= 1
    when :attending
      # 通常参加は到着1Rが自然（未指定でもOK）
      self.arrival_round ||= 1
    when :absent
      # 不参加は出場不可になるよう round をクリア
      self.arrival_round = nil
      self.leave_round   = nil
    when :undecided
      # 未定はそのまま（編成に入れるかはスコープ側で管理）
    end
  end
end