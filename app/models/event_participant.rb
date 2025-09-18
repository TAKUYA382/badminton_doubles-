# app/models/event_participant.rb
class EventParticipant < ApplicationRecord
  # ================================
  # ステータス管理
  # ================================
  # 0: 未定, 1: 参加, -1: 欠席
  enum status: {
    undecided: 0,   # 未定
    attending: 1,   # 参加
    absent: -1      # 欠席
  }

  # ================================
  # アソシエーション
  # ================================
  belongs_to :event
  belongs_to :member

  # ================================
  # バリデーション
  # ================================
  # 同じイベントに同じメンバーを重複登録させない
  validates :event_id, uniqueness: { scope: :member_id }

  # ================================
  # スコープ
  # ================================
  # 参加予定者のみ
  scope :only_attending, -> { where(status: statuses[:attending]) }

  # 未定 or 参加
  scope :active_for_schedule, -> { where(status: [statuses[:attending], statuses[:undecided]]) }

  # ================================
  # ラベル系
  # ================================
  def status_label
    case status.to_sym
    when :attending then "参加"
    when :undecided then "未定"
    when :absent    then "欠席"
    else "-"
    end
  end

  # イベント＋メンバーを日本語表記
  def display_name
    "#{event.title} - #{member.name}"
  end
end