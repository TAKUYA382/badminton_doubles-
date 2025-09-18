# app/controllers/admin/matches_controller.rb
class Admin::MatchesController < Admin::BaseController
  protect_from_forgery with: :exception

  # ================================
  # 並び替え
  # ================================
  def reorder
    params[:match_ids].each_with_index do |id, index|
      Match.where(id: id).update_all(position: index + 1)
    end
    head :ok
  end

  # ================================
  # 指定スロットを空にする
  # ================================
  def clear_slot
    match = Match.find(params[:id])
    slot  = params[:slot].to_s
    match.clear_slot!(slot)
    render json: { ok: true }
  end

  # ================================
  # 指定スロットにメンバーを入れる（簡易バリデーション付き）
  # ================================
  def replace_member
    match     = Match.find(params[:id])
    slot      = params[:slot].to_s
    member_id = params[:member_id].to_i

    # ラウンド内で重複禁止
    if match.member_already_used_in_round?(member_id)
      return render json: { ok: false, error: "同じラウンドで重複しています" }, status: :unprocessable_entity
    end

    match.replace_slot!(slot, member_id)
    render json: { ok: true, has_ng: match.has_ng_relation? }
  end

  # ================================
  # ★ 追加：2スロットをまとめて入れ替え（DnD対応）
  # ================================
  def swap
    # 例:
    # params = {
    #   source_match_id: 1, source_slot: "pair1_member1",
    #   target_match_id: 2, target_slot: "pair2_member2"
    # }

    source_match = Match.find(params[:source_match_id])
    target_match = Match.find(params[:target_match_id])
    source_slot  = params[:source_slot].to_s
    target_slot  = params[:target_slot].to_s

    # === 同じラウンド内でない場合はエラー ===
    if source_match.round_id != target_match.round_id
      return render json: { ok: false, error: "異なるラウンド間では入れ替えできません" }, status: :unprocessable_entity
    end

    # 現在のメンバーを保持
    source_member = source_match.send(source_slot)
    target_member = target_match.send(target_slot)

    # 両方が空なら意味なし
    if source_member.nil? && target_member.nil?
      return render json: { ok: false, error: "どちらも空のため入れ替えできません" }, status: :unprocessable_entity
    end

    ActiveRecord::Base.transaction do
      # 1. まず片方を一時的にnilにして重複エラーを避ける
      source_match.update!(source_slot => nil)

      # 2. それぞれ更新
      source_match.update!(source_slot => target_member&.id)
      target_match.update!(target_slot => source_member&.id)
    end

    render json: { ok: true, message: "入れ替えが完了しました" }
  rescue ActiveRecord::RecordInvalid => e
    render json: { ok: false, error: e.record.errors.full_messages.join(", ") }, status: :unprocessable_entity
  rescue => e
    render json: { ok: false, error: e.message }, status: :internal_server_error
  end
end