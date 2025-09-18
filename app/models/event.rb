class Event < ApplicationRecord
  # ================================
  # ラウンド管理
  # ================================
  has_many :rounds, dependent: :destroy
  has_many :matches, through: :rounds

  # ================================
  # 出欠管理（旧機能：Attendance）
  # ================================
  has_many :attendances, dependent: :destroy
  has_many :attending_members,
           -> { where(attendances: { status: Attendance.statuses[:attending] }) },
           through: :attendances,
           source: :member

  # ================================
  # 参加者管理（新機能：EventParticipant）
  # ================================
  has_many :event_participants, dependent: :destroy
  has_many :participants, through: :event_participants, source: :member

  # ================================
  # ステータス管理
  # ================================
  enum status: { draft: 0, published: 1, archived: 2 }, _prefix: true

  # ================================
  # バリデーション
  # ================================
  validates :title, :date, :court_count, presence: true
  validates :court_count, numericality: { greater_than: 0 }
end