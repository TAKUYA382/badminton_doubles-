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
  # ================================
  # 期待パラメータ例:
  # {
  #   "changes": [
  #     { "match_id": 12, "slots": { "pair1_member1": 101, "pair1_member2": null } },
  #     { "match_id": 13, "slots": { "pair2_member1": 205 } }
  #   ]
  # }
  #
  # - null/"" はクリアとして扱う
  # - モデル側の replace_slot! / clear_slot! を利用（重複/NG等のバリデーションはモデル責務）
  # - 成功時: Turbo Stream で各試合カードを replace
  # ================================
  def bulk_update
    changes = params.require(:changes)
    updated_matches = []

    ActiveRecord::Base.transaction do
      changes.each do |change|
        match = Match.lock.find(change[:match_id] || change["match_id"])
        slots = change[:slots] || change["slots"] || {}

        slots.each do |slot, raw_val|
          slot = slot.to_s
          if raw_val.blank?
            match.clear_slot!(slot)
          else
            member_id = raw_val.to_i
            # 同ラウンド重複の簡易チェック（モデルで厳密チェックしているなら省略可）
            if match.member_already_used_in_round?(member_id)
              raise ActiveRecord::RecordInvalid.new(match), "同じラウンドで重複しています（#{member_id}）"
            end
            match.replace_slot!(slot, member_id)
          end
        end

        updated_matches << match.reload
      end
    end

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream_updates_for(updated_matches)
      end
      format.json { render json: { ok: true, updated_ids: updated_matches.map(&:id) } }
      format.html do
        event = updated_matches.first&.round&.event
        redirect_to(event ? admin_event_path(event) : admin_root_path, notice: "更新しました")
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream_flash(:alert, e.record.errors.full_messages.join(", ")), status: :unprocessable_entity }
      format.json         { render json: { ok: false, error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity }
      format.html         { redirect_back fallback_location: admin_root_path, alert: e.record.errors.full_messages.join(", ") }
    end
  rescue ActionController::ParameterMissing => e
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream_flash(:alert, "changes パラメータが不正です"), status: :bad_request }
      format.json         { render json: { ok: false, error: "changes パラメータが不正です" }, status: :bad_request }
      format.html         { redirect_back fallback_location: admin_root_path, alert: "changes パラメータが不正です" }
    end
  rescue => e
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream_flash(:alert, e.message), status: :internal_server_error }
      format.json         { render json: { ok: false, error: e.message }, status: :internal_server_error }
      format.html         { redirect_back fallback_location: admin_root_path, alert: e.message }
    end
  end

  private

  # 更新済みカードをまとめて差し替える Turbo Stream を生成
  def turbo_stream_updates_for(matches)
    streams = matches.map do |m|
      turbo_stream.replace(
        dom_id(m),
        partial: "admin/matches/card",
        locals: { match: m }
      )
    end
    # ついでにフラッシュも出す（任意）
    streams << turbo_stream_flash(:notice, "まとめて更新しました（#{matches.size}件）")
    streams
  end

  # 簡易フラッシュ（Turbo Stream）
  def turbo_stream_flash(kind, message)
    turbo_stream.replace(
      "flash",
      partial: "shared/flash",
      locals: { flash: { kind => message } }
    )
  end
end 