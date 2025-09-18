# app/controllers/admin/event_participants_imports_controller.rb
class Admin::EventParticipantsImportsController < Admin::BaseController
  before_action :set_event

  # ===== ペースト入力画面 =====
  def paste_form
    # 単純にフォーム表示だけ
  end

  # ===== プレビュー =====
  def preview
    # ここを修正: 先頭に :: を付けてトップレベルの NameMatcher を呼ぶ
    matcher = ::NameMatcher.new(scope: Member.active)
    @rows   = matcher.preview(matcher.parse_lines(params[:bulk_text]))
    # @rows の各要素:
    #   {
    #     raw:,           # 元の文字列
    #     name:,          # 名前部分
    #     normalized:,    # 正規化された名前
    #     status:,        # 出欠ステータス
    #     match:,         # :unique / :none / :ambiguous
    #     member: or candidates:[]
    #   }
    render :preview
  end

  # ===== 取り込み確定 =====
  def commit
    matcher = ::NameMatcher.new(scope: Member.active)
    items   = matcher.parse_lines(params[:bulk_text])
    rows    = matcher.preview(items)

    created = 0
    skipped = []

    ActiveRecord::Base.transaction do
      rows.each do |row|
        case row[:match]
        when :unique
          # 該当メンバーがイベントに紐づいていなければ作成
          EventParticipant.find_or_create_by!(event: @event, member: row[:member]) do |ep|
            ep.status = row[:status]
          end.tap do |ep|
            # 既存ならステータスを更新
            ep.update!(status: row[:status]) if ep.persisted? && ep.status.to_sym != row[:status]
          end
          created += 1
        else
          # 未一致 or 複数一致は保留
          skipped << row
        end
      end
    end

    redirect_to admin_event_path(@event),
                notice: "取り込み完了：#{created}件 / 保留：#{skipped.size}件"

  rescue ActiveRecord::RecordInvalid => e
    redirect_to paste_participants_admin_event_path(@event),
                alert: "取り込みに失敗しました：#{e.message}"
  end

  private

  def set_event
    @event = Event.find(params[:id])
  end
end