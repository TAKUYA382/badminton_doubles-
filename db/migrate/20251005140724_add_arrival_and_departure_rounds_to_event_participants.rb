class AddArrivalAndDepartureRoundsToEventParticipants < ActiveRecord::Migration[7.2]
  def change
    add_column :event_participants, :arrival_round, :integer
    add_column :event_participants, :departure_round, :integer
  end
end
