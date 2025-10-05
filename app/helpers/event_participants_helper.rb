module EventParticipantsHelper
  def participant_range_label(ep, total_rounds: nil)
    return content_tag(:span, "（不参加）", class: "pill pill-gray") if ep.absent?

    ar = ep.arrival_round
    lr = ep.leave_round

    left  = ar.present? ? "到着#{ar}R" : "到着1R"
    right = lr.present? ? "退出#{lr}R" : "制限なし"

    klass =
      if ep.late?
        "pill pill-late"
      elsif ep.early_leave?
        "pill pill-early"
      else
        "pill pill-ok"
      end

    content_tag(:span, "#{left} → #{right}", class: klass)
  end
end