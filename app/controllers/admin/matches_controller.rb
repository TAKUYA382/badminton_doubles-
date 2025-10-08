# app/controllers/admin/matches_controller.rb
class Admin::MatchesController < Admin::BaseController
  protect_from_forgery with: :exception

  # ================================
  # 並び替え（任意）
  # ================================
  def reorder
    params[:match_ids].each_with_index do |id, index|
      Match.where(id: id).update_all(position: index + 1)
    end
    head :ok
  end

  # ================================
  # 指定スロットを空にする（単発API）
  # ================================
  def clear_slot
    match = Match.find(params[:id])
    slot  = params[:slot].to_s
    match.clear_slot!(slot)
    render json: { ok: true }
  end

  # ================================
  # 指定スロット差し替え（単発API）
  # ================================
  def replace_member
    match     = Match.find(params[:id])
    slot      = params[:slot].to_s
    member_id = params[:member_id].to_i

    if match.member_already_used_in_round?(member_id)
      return render json: { ok: false, error: "同じラウンドで重複しています" }, status: :unprocessable_entity
    end

    match.replace_slot!(slot, member_id)
    render json: { ok: true, has_ng: match.has_ng_relation? }
  end

  # ================================
  # 2スロット入れ替え（DnD）
  # ================================
  def swap
    source_match = Match.find(params[:source_match_id])
    target_match = Match.find(params[:target_match_id])
    source_slot  = params[:source_slot].to_s
    target_slot  = params[:target_slot].to_s

    if source_match.round_id != target_match.round_id
      return render json: { ok: false, error: "異なるラウンド間では入れ替えできません" }, status: :unprocessable_entity
    end

    source_member = source_match.send(source_slot)
    target_member = target_match.send(target_slot)

    if source_member.nil? && target_member.nil?
      return render json: { ok: false, error: "どちらも空のため入れ替えできません" }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      source_match.update!(source_slot => nil)
      source_match.update!(source_slot => target_member&.id)
      target_match.update!(target_slot => source_member&.id)
    end

    render json: { ok: true, message: "入れ替えが完了しました" }
  rescue ActiveRecord::RecordInvalid => e
    render json: { ok: false, error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  rescue => e
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end

  # ================================
  # ★ まとめて更新（バッファ適用）
  # Stimulus lineup_controller.js が送る JSON 例:
  # POST /admin/matches/bulk_update
  # {
  #   "event_id": 99,
  #   "operations": [
  #     { "type":"replace", "match_id": 12, "slot_key":"pair1_member1", "member_id": 101 },
  #     { "type":"clear",   "match_id": 12, "slot_key":"pair2_member2", "member_id": null },
  #     { "type":"replace", "match_id": 13, "slot_key":"pair2_member1", "member_id": 205 }
  #   ]
  # }
  # ================================
  def bulk_update
    ops = params.require(:operations)
    raise ActionController::ParameterMissing, "operations は配列で送ってください" unless ops.is_a?(Array)

    # 同一試合の更新をまとめてロック＆順適用するためにグルーピング
    grouped = ops.group_by { |o| (o[:match_id] || o["match_id"]).to_i }
    updated_matches = []

    ActiveRecord::Base.transaction do
      grouped.each do |match_id, operations|
        match = Match.lock.find(match_id)

        operations.each do |op|
          type     = (op[:type] || op["type"]).to_s
          slot_key = (op[:slot_key] || op["slot_key"]).to_s
          member_v =  op[:member_id].presence || op["member_id"].presence

          unless valid_slot?(slot_key)
            raise ActiveRecord::RecordInvalid.new(match), "不正なスロットです（#{slot_key}）"
          end

          case type
          when "clear"
            match.clear_slot!(slot_key)

          when "replace"
            member_id = member_v.to_i
            if member_id <= 0
              raise ActiveRecord::RecordInvalid.new(match), "メンバーIDが不正です"
            end

            # 同ラウンド重複の簡易チェック（モデル側で厳密チェックしているなら不要）
            if match.member_already_used_in_round?(member_id)
              raise ActiveRecord::RecordInvalid.new(match), "同じラウンドで重複しています（ID: #{member_id}）"
            end

            match.replace_slot!(slot_key, member_id)

          else
            raise ActiveRecord::RecordInvalid.new(match), "不明な操作タイプです（#{type}）"
          end
        end

        updated_matches << match.reload
      end
    end

    respond_to do |format|
      # Turbo Stream：更新カードをまとめて差し替え & フラッシュ
      format.turbo_stream do
        render turbo_stream: turbo_stream_updates_for(updated_matches)
      end
      format.json { render json: { ok: true, updated_ids: updated_matches.map(&:id) } }
      format.html do
        event = updated_matches.first&.round&.event || Event.find_by(id: params[:event_id])
        redirect_to(event ? admin_event_path(event) : admin_root_path, notice: "まとめて更新しました（#{updated_matches.size}件）")
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    message = e.record.errors.full_messages.presence&.join(", ") || e.message
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream_flash(:alert, message), status: :unprocessable_entity }
      format.json         { render json: { ok: false, error: message }, status: :unprocessable_entity }
      format.html         { redirect_back fallback_location: admin_root_path, alert: message }
    end
  rescue ActionController::ParameterMissing => e
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream_flash(:alert, e.message), status: :bad_request }
      format.json         { render json: { ok: false, error: e.message }, status: :bad_request }
      format.html         { redirect_back fallback_location: admin_root_path, alert: e.message }
    end
  rescue => e
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream_flash(:alert, e.message), status: :internal_server_error }
      format.json         { render json: { ok: false, error: e.message }, status: :internal_server_error }
      format.html         { redirect_back fallback_location: admin_root_path, alert: e.message }
    end
  end

  private

  # 許可スロット
  def valid_slot?(key)
    %w[pair1_member1 pair1_member2 pair2_member1 pair2_member2].include?(key)
  end

  # 更新済みカードをまとめて差し替える Turbo Stream を生成
  def turbo_stream_updates_for(matches)
    streams = matches.map do |m|
      turbo_stream.replace(
        dom_id(m),
        partial: "admin/matches/card",
        locals: { match: m }
      )
    end
    streams << turbo_stream_flash(:notice, "まとめて更新しました（#{matches.size}件）")
    streams
  end

  # 簡易フラッシュ（Turbo Stream）
  # ※ layouts 等に <div id="flash"></div> を置いておくと差し替えられます
  def turbo_stream_flash(kind, message)
    turbo_stream.replace(
      "flash",
      partial: "shared/flash",
      locals: { flash: { kind => message } }
    )
  end
end