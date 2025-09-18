class EventsController < ApplicationController
  def index
    @events = Event.status_published.order(date: :desc)
  end

  def show
    @event = Event.includes(rounds: :matches).find(params[:id])
  end
end
