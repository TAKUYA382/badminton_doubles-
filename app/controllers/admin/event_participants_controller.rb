# app/controllers/admin/event_participants_controller.rb
class Admin::EventParticipantsController < Admin::BaseController
  before_action :set_event
  before_action :set_event_participant, only: [:update, :destroy]

  # 一覧：このイベントの参加状況を編集
  def index
    # 左：登録済み
    @event_participants = @event.event_participants
                               .includes(:member)
                               .references(:member)
                               .merge(Member.order(:name))

    # 右：未登録候補（検索付き）
    q = params[:q].to_s.strip
    scope = Member.active.order(:name)
    scope = scope.name_like(q) if q.present?

    registered_ids = @event_participants.map(&:member_id)
    @candidates = scope.where.not(id: registered_ids)
  end

  # 新規登録（このイベントにメンバーを追加）
  def create
    # member_id をキーに既存を拾う or 新規
    ep = @event.event_participants.find_or_initialize_by(
      member_id: event_participant_params[:member_id]
    )
    # member_id は find_or_initialize_by に使ったので、それ以外を代入
    ep.assign_attributes(event_participant_params.except(:member_id))
    ep.status ||= :undecided
    ep.save!

    redirect_to admin_event_attendances_path(@event),
                notice: "参加者を追加しました（#{ep.member.name}: #{ep.status}）"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_event_attendances_path(@event),
                alert: "追加に失敗: #{e.record.errors.full_messages.join(', ')}"
  end

  # ステータス・到着/退出ラウンド更新
  def update
    @event_participant.update!(event_participant_params)
    redirect_to admin_event_attendances_path(@event),
                notice: "更新しました（#{@event_participant.member.name}: #{@event_participant.status}）"
  rescue ActiveRecord::RecordInvalid => e
    redirect_to admin_event_attendances_path(@event),
                alert: "更新に失敗: #{e.record.errors.full_messages.join(', ')}"
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

  # ★ここが追加（Strong Parameters）
  # 到着/退出ラウンドも許可する。空文字は nil にしてモデルの allow_nil に載せる。
  def event_participant_params
    raw = params.require(:event_participant)
                .permit(:member_id, :status, :arrival_round, :leave_round)

    # "" が来たら nil に正規化（数値にしなくてOK。モデルで allow_nil）
    raw[:arrival_round] = nil if raw[:arrival_round].blank?
    raw[:leave_round]   = nil if raw[:leave_round].blank?
    raw
  end
end