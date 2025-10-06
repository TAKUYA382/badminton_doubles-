# app/controllers/admin/event_participants_controller.rb
class Admin::EventParticipantsController < Admin::BaseController
  before_action :set_event
  before_action :set_event_participant, only: [:update, :destroy]

  # 一覧：このイベントの参加状況を編集
  def index
    # 左：登録済み（名前順）
    @event_participants = @event.event_participants
                               .includes(:member)
                               .order("members.name")

    # 右：未登録候補（検索付き）
    q = params[:q].to_s.strip
    scope = Member.active.order(:name)
    scope = scope.name_like(q) if q.present?

    registered_ids = @event_participants.map(&:member_id)
    @candidates = scope.where.not(id: registered_ids)
  end

  # 新規登録（このイベントにメンバーを追加）
  def create
    ep = @event.event_participants.find_or_initialize_by(
      member_id: safe_params[:member_id]
    )
    ep.assign_attributes(safe_params.except(:member_id))
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
    @event_participant.update!(safe_params)
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

  # -------- ここがポイント: フォーム形状の違いに強い Strong Params --------
  #
  # 1) ネスト形式: params[:event_participant][:status], [:arrival_round], [:leave_round]
  # 2) フラット形式: params[:status], [:arrival_round], [:leave_round], [:member_id]
  # どちらでも受け取れるようにし、空文字は nil に正規化します。
  def safe_params
    permitted =
      if params[:event_participant].is_a?(ActionController::Parameters)
        params.require(:event_participant)
              .permit(:member_id, :status, :arrival_round, :leave_round)
      else
        params.permit(:member_id, :status, :arrival_round, :leave_round)
      end

    # "" → nil（モデル側で allow_nil / before_validation を使いやすくする）
    permitted[:arrival_round] = nil if permitted[:arrival_round].blank?
    permitted[:leave_round]   = nil if permitted[:leave_round].blank?

    permitted
  end
end