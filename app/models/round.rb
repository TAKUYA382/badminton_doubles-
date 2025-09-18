class Round < ApplicationRecord
  belongs_to :event
  has_many :matches, dependent: :destroy

  enum status: { scheduled: 0, finished: 1 }, _prefix: true
  validates :index, presence: true, numericality: { greater_than: 0 }
end
