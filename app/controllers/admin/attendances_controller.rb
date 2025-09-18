# app/controllers/admin/attendances_controller.rb
class Admin::AttendancesController < Admin::BaseController
  before_action :set_event

  # ================================
  # 出欠一覧（このイベントだけ）
  # ================================
  def index
    # 全メンバーを表示して、@attendance_map に出欠をマッピング
    @members = Member.order(:id)
    @attendance_map = @event.attendances.includes(:member).index_by(&:member_id)
  end

  # ================================
  # 新規登録（参加/未定/欠席）
  # ================================
  def create
    upsert_attendance!
    redirect_back fallback_location: admin_event_attendances_path(@event), notice: '出欠を保存しました。'
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: admin_event_attendances_path(@event), alert: "保存に失敗しました: #{e.message}"
  end

  # ================================
  # 更新（参加→欠席など変更時）
  # ================================
  def update
    upsert_attendance!
    redirect_back fallback_location: admin_event_attendances_path(@event), notice: '出欠を更新しました。'
  rescue ActiveRecord::RecordInvalid => e
    redirect_back fallback_location: admin_event_attendances_path(@event), alert: "更新に失敗しました: #{e.message}"
  end

  # ================================
  # 削除（クリア）
  # ================================
  def destroy
    attendance = @event.attendances.find_by!(member_id: params[:member_id])
    attendance.destroy!
    redirect_back fallback_location: admin_event_attendances_path(@event), notice: '出欠を削除しました。'
  rescue ActiveRecord::RecordNotFound
    redirect_back fallback_location: admin_event_attendances_path(@event), alert: '出欠が見つかりませんでした。'
  end

  private

  # 対象イベントをセット
  def set_event
    @event = Event.find(params[:event_id])
  end

  # ================================
  # 共通メソッド：出欠Upsert
  # ================================
  # member_id, status, note を受け取り、
  # 存在すれば更新、なければ新規作成
  def upsert_attendance!
    attendance = @event.attendances.find_or_initialize_by(member_id: attendance_params[:member_id])
    attendance.assign_attributes(attendance_params)
    attendance.save!
  end

  # Strong Parameters
  def attendance_params
    params.require(:attendance).permit(:member_id, :status, :note)
  end
end