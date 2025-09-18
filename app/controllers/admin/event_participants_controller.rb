class Admin::EventParticipantsController < Admin::BaseController
  before_action :set_event
  before_action :set_event_participant, only: [:update, :destroy]

  # 一覧：このイベントの参加状況を編集
  def index
    # 画面左に「このイベントの登録済み参加者」
    @event_participants = @event.event_participants.includes(:member).order("members.name")

    # 右側の「未登録メンバー一覧」用（検索付き）
    q = params[:q].to_s.strip
    scope = Member.active.order(:name)
    scope = scope.name_like(q) if q.present?

    # すでに登録済みのメンバーは除外
    registered_ids = @event_participants.map(&:member_id)
    @candidates = scope.where.not(id: registered_ids)
  end

  # 新規登録（このイベントにメンバーを追加）
  def create
    ep = @event.event_participants.find_or_initialize_by(member_id: params[:member_id])
    ep.status = params[:status].presence || :undecided
    ep.save!
    redirect_to admin_event_attendances_path(@event), notice: "参加者を追加しました（#{ep.member.name}: #{ep.status}）"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_event_attendances_path(@event), alert: "追加に失敗: #{e.record.errors.full_messages.join(', ')}"
  end

  # ステータス更新
  def update
    @event_participant.update!(status: params[:status])
    redirect_to admin_event_attendances_path(@event), notice: "更新しました（#{@event_participant.member.name}: #{@event_participant.status}）"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_event_attendances_path(@event), alert: "更新に失敗: #{e.record.errors.full_messages.join(', ')}"
  end

  # 削除（このイベントから外す）
  def destroy
    name = @event_participant.member.name
    @event_participant.destroy!
    redirect_to admin_event_attendances_path(@event), notice: "削除しました（#{name}）"
  end

  private
  def set_event
    @event = Event.find(params[:event_id])
  end

  def set_event_participant
    @event_participant = @event.event_participants.find(params[:id])
  end
end