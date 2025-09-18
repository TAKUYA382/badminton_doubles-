# app/controllers/admin/events_controller.rb
class Admin::EventsController < Admin::BaseController
  before_action :set_event, only: %i[
    show edit update destroy publish unpublish auto_schedule update_slot
  ]

  # 一覧
  def index
    @events = Event.order(date: :desc)
  end

  # 詳細
  def show
    # 参加回数カウント（現行のまま）
    counts = Hash.new(0)
    @event.rounds.each do |r|
      r.matches.each do |m|
        [m.pair1_member1, m.pair1_member2, m.pair2_member1, m.pair2_member2].compact.each { |mem| counts[mem] += 1 }
      end
    end
    @participations = counts.to_a.sort_by { |(mem, c)| [-c, mem.name] }

    # ▼ 変更点：ドラッグ候補＝このイベントで「参加(attending)」のメンバーだけ
    # もし全員候補で見たい時は /admin/events/:id?all=1 にアクセス（任意）
    use_all = params[:all].to_s == "1"
    scope   = use_all ? Member.active : participants_scope_for(@event) # ← attending だけ

    # ビューで使う候補
    @drag_members    = scope.order(:name)                 # 丸いチップのドラッグ元
    @all_members     = @drag_members                      # 既存の部分が @all_members を見ていても動くように合わせておく
    @available_members = available_members(scope)         # 「未使用のみ」を同じスコープで
  end

  # 新規
  def new
    @event = Event.new(date: Date.today, court_count: 2)
  end

  def create
    @event = Event.new(event_params)
    if @event.save
      redirect_to admin_event_path(@event), notice: "イベントを作成しました"
    else
      render :new, status: :unprocessable_entity
    end
  end

  # 編集
  def edit; end

  def update
    if @event.update(event_params)
      redirect_to admin_event_path(@event), notice: "イベントを更新しました"
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # 削除
  def destroy
    @event.destroy
    redirect_to admin_events_path, notice: "イベントを削除しました"
  end

  # 公開/非公開
  def publish
    if @event.update(status: :published)
      redirect_to admin_event_path(@event), notice: "イベントを公開しました"
    else
      redirect_to admin_event_path(@event), alert: "公開に失敗しました"
    end
  end

  def unpublish
    if @event.update(status: :draft)
      redirect_to admin_event_path(@event), notice: "イベントを非公開にしました"
    else
      redirect_to admin_event_path(@event), alert: "非公開に失敗しました"
    end
  end

  # 自動編成
  def auto_schedule
    rounds = params[:rounds].to_i
    rounds = nil if rounds <= 0
    mode   = params[:mode] || "split"

    result = ::Scheduling::AutoSchedule.new(@event, target_rounds: rounds, mode: mode).call
    if result.success?
      redirect_to admin_event_path(@event), notice: "対戦表を作成しました（#{@event.rounds.count}回戦）"
    else
      redirect_to admin_event_path(@event), alert: result.error_message
    end
  end

  # スロット編集
  def update_slot
    match     = Match.includes(:round).find(params[:match_id])
    slot      = params[:slot_key].to_s
    clear     = params[:clear].present?
    member_id = params[:member_id].presence

    unless %w[pair1_member1 pair1_member2 pair2_member1 pair2_member2].include?(slot)
      return respond_update_slot_error!("不正なスロット指定です")
    end

    if clear
      match.clear_slot!(slot)
      return respond_update_slot_ok!("スロットを空にしました")
    end

    new_member = Member.find_by(id: member_id)
    return respond_update_slot_error!("メンバーが選択されていません") unless new_member

    if match.members.compact.map(&:id).include?(new_member.id)
      return respond_update_slot_error!("同じ試合に同一メンバーは配置できません")
    end

    partner, opponents = teammates_and_opponents_for(match, slot)

    if partner && relation_blocked?(new_member.id, partner.id, :avoid_pair)
      return respond_update_slot_error!("ペアNGの組み合わせです（#{new_member.name} × #{partner.name}）")
    end

    if opponents.any? { |op| relation_blocked?(new_member.id, op.id, :avoid_opponent) }
      names = opponents.select { |op| relation_blocked?(new_member.id, op.id, :avoid_opponent) }.map(&:name).join("・")
      return respond_update_slot_error!("対戦NGの組み合わせです（#{new_member.name} vs #{names}）")
    end

    match.replace_member!(slot, new_member.id)
    respond_update_slot_ok!("メンバーを差し替えました")
  rescue ActiveRecord::RecordInvalid => e
    respond_update_slot_error!(e.record.errors.full_messages.join(", "))
  end

  private

  def respond_update_slot_ok!(notice)
    respond_to do |format|
      format.json { render json: { ok: true, notice: notice } }
      format.html { redirect_to admin_event_path(@event), notice: notice }
    end
  end

  def respond_update_slot_error!(message)
    respond_to do |format|
      format.json { render json: { ok: false, error: message }, status: :unprocessable_entity }
      format.html { redirect_to admin_event_path(@event), alert: message }
    end
  end

  def set_event
    @event = Event.includes(rounds: :matches).find(params[:id])
  end

  def event_params
    params.require(:event).permit(:title, :date, :court_count, :status)
  end

  # 未使用メンバーのみ（与えられたベーススコープ内で）
  def available_members(base_scope)
    used_ids = @event.rounds.flat_map { |r| r.matches.flat_map(&:members) }.compact.map(&:id)
    base_scope.where.not(id: used_ids).order(:name)
  end

  # ★ 参加者スコープ：このイベントで「attending」になっているメンバーのみ
  #   ※ EventParticipant を使う構成前提。Attendances を使っていない点に注意。
  def participants_scope_for(event)
    ids = event.event_participants.attending.pluck(:member_id).uniq
    Member.active.where(id: ids)
  end

  # NG関係チェック（双方向）
  def relation_blocked?(a_id, b_id, kind)
    MemberRelation.where(kind: MemberRelation.kinds[kind])
                  .where("(member_id = :a AND other_member_id = :b) OR (member_id = :b AND other_member_id = :a)", a: a_id, b: b_id)
                  .exists?
  end

  # スロットから味方/相手を判定
  def teammates_and_opponents_for(match, slot_key)
    case slot_key
    when "pair1_member1" then [match.pair1_member2, [match.pair2_member1, match.pair2_member2].compact]
    when "pair1_member2" then [match.pair1_member1, [match.pair2_member1, match.pair2_member2].compact]
    when "pair2_member1" then [match.pair2_member2, [match.pair1_member1, match.pair1_member2].compact]
    when "pair2_member2" then [match.pair2_member1, [match.pair1_member1, match.pair1_member2].compact]
    else [nil, []]
    end
  end
end