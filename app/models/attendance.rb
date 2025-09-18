class Attendance < ApplicationRecord
  belongs_to :event
  belongs_to :member

  enum status: { undecided: 0, attending: 1, absent: 2 }

  validates :event_id,  presence: true
  validates :member_id, presence: true
  validates :status,    presence: true
  validates :member_id, uniqueness: { scope: :event_id } # 同一イベントで重複不可
end
