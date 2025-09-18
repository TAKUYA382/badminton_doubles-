class Admin::MemberRelationsController < Admin::BaseController
  def create
    mr = params.require(:member_relation)
    member_id = mr[:member_id]
    other_id  = mr[:other_member_id]

    # チェックボックス（複数）優先。古い単一select対応もフォールバックでサポート
    kinds = Array(mr[:kinds]).presence || Array(mr[:kind]).presence

    if kinds.blank?
      return redirect_back fallback_location: admin_members_path, alert: "種別を選択してください（ペアNG/対戦NG）"
    end

    created = 0
    errors  = []

    kinds.each do |kind_str|
      # enumのキーを許容（"avoid_pair" / "avoid_opponent"）
      kind_val = MemberRelation.kinds[kind_str]
      unless kind_val
        errors << "#{kind_str}: 不正な種別です"
        next
      end

      rel = MemberRelation.new(member_id: member_id, other_member_id: other_id, kind: kind_val)
      if rel.save
        created += 1
      else
        errors << "#{Member.find_by(id: other_id)&.name || '相手未選択'}(#{kind_str}): #{rel.errors.full_messages.to_sentence}"
      end
    end

    if created > 0
      msg = "#{created}件登録しました"
      msg += "（一部失敗: #{errors.join(' / ')}）" if errors.any?
      redirect_back fallback_location: admin_members_path, notice: msg
    else
      redirect_back fallback_location: admin_members_path, alert: errors.presence || "登録に失敗しました"
    end
  end

  def destroy
    rel = MemberRelation.find(params[:id])
    rel.destroy
    redirect_back fallback_location: admin_members_path, notice: "関係を削除しました"
  end
end
