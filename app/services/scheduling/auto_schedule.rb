# app/services/scheduling/auto_schedule.rb
# frozen_string_literal: true

require "set"

module Scheduling
  # 成否とエラーメッセージだけを返す薄い結果クラス
  class Result < Struct.new(:success?, :error_message); end

  class AutoSchedule
    # mode: "split"（男女別） / "mixed"（MIX）
    # target_rounds: 生成するラウンド数（nil なら 1）
    def initialize(event, target_rounds: nil, mode: "split")
      @event         = event
      @courts        = event.court_count.to_i
      @members       = pick_base_members(event) # 「不参加以外」のメンバー
      @target_rounds = (target_rounds.presence || 1).to_i
      @mode          = mode.to_s
      @ep_cache      = {} # member_id => EventParticipant
    end

    def call
      @played_counts = Hash.new(0)

      return Result.new(false, "このイベントの参加者（不参加以外）が4名以上必要です") if @members.size < 4
      return Result.new(false, "コート数が1以上必要です") if @courts < 1

      ActiveRecord::Base.transaction do
        # --- 既存の編成を完全削除（子→親の順で物理削除）---
        round_ids = @event.rounds.pluck(:id)
        Match.where(round_id: round_ids).delete_all if round_ids.any?
        Round.where(id: round_ids).delete_all

        case @mode
        when "split" then schedule_split_ranked!
        when "mixed" then schedule_mixed_balanced!
        else
          raise ArgumentError, "未知のメイキングモード: #{@mode}"
        end
      end

      Result.new(true, nil)
    rescue => e
      # 例外を握りつぶして Result として返す（UI側にメッセージ）
      Result.new(false, e.message)
    end

    private

    # ===============================
    # 参加者抽出：「不参加」以外（attending/late/early_leave/undecided）
    # ===============================
    def pick_base_members(event)
      absent_value =
        if defined?(EventParticipant) && EventParticipant.respond_to?(:statuses)
          EventParticipant.statuses["absent"] rescue nil
        end

      scope = event.event_participants.includes(:member)
      scope = absent_value ? scope.where.not(status: absent_value) : scope.where.not(status: :absent)

      eps = scope.to_a
      @ep_cache ||= {}

      # memberがnilな参加者は無視（削除済みメンバー対策）
      eps.each do |ep|
        next unless ep&.member_id && ep&.member
        @ep_cache[ep.member_id] = ep
      end

      eps.map(&:member).compact.uniq
    end

    # ===============================
    # ラウンド在席判定（1-indexed）
    # arrival_round / leave_round / arrival / leave に対応
    # ===============================
    def available_on_round?(member, round_idx)
      ep = @ep_cache[member.id] || @event.event_participants.find_by(member_id: member.id)
      return false unless ep

      arr = if ep.respond_to?(:arrival_round) && ep.arrival_round.present?
              ep.arrival_round
            elsif ep.respond_to?(:arrival) && ep.arrival.present?
              ep.arrival
            end

      dep = if ep.respond_to?(:leave_round) && ep.leave_round.present?
              ep.leave_round
            elsif ep.respond_to?(:departure_round) && ep.departure_round.present?
              ep.departure_round
            elsif ep.respond_to?(:leave) && ep.leave.present?
              ep.leave
            end

      arr_i = arr.to_i if arr
      dep_i = dep.to_i if dep

      arrived  = arr.nil? || arr_i <= 0 || arr_i <= round_idx
      not_left = dep.nil? || dep_i <= 0 || round_idx <= dep_i
      !!(arrived && not_left)
    end

    # ===============================
    # 男女別：男子→女子の順に強いカードから詰める
    # ===============================
    def schedule_split_ranked!
      male_courts   = (@courts / 2.0).ceil
      female_courts = @courts - male_courts

      1.upto(@target_rounds) do |round_idx|
        round      = @event.rounds.create!(index: round_idx)
        used_round = Set.new
        made       = []

        avail   = @members.select { |m| available_on_round?(m, round_idx) }
        males   = avail.select { |m| gender_of(m) == :male }
        females = avail.select { |m| gender_of(m) == :female }

        # 男子
        (1..male_courts).each do |pos|
          desired = band_for_position(pos)
          quad    = pick_quad_for_gender_and_band(males, desired, used_round)
          break if quad.size < 4
          p1, p2 = best_pairing_for_quad(quad, desired)
          made << [:male, desired, p1, p2]
          mark_used!(quad, used_round)
        end

        # 女子
        (1..female_courts).each do |pos|
          desired = band_for_position(pos)
          quad    = pick_quad_for_gender_and_band(females, desired, used_round)
          break if quad.size < 4
          p1, p2 = best_pairing_for_quad(quad, desired)
          made << [:female, desired, p1, p2]
          mark_used!(quad, used_round)
        end

        male_made   = made.select { |sex, *_| sex == :male }.sort_by { |_s, band, p1, p2| [-band, -match_strength(p1, p2)] }
        female_made = made.select { |sex, *_| sex == :female }.sort_by { |_s, band, p1, p2| [-band, -match_strength(p1, p2)] }

        court_no = 1
        male_made.each do |_s, _b, p1, p2|
          break if court_no > @courts
          create_match!(round, court_no, p1, p2)
          court_no += 1
        end
        female_made.each do |_s, _b, p1, p2|
          break if court_no > @courts
          create_match!(round, court_no, p1, p2)
          court_no += 1
        end
      end
    end

    def band_for_position(pos)
      { 1 => 4, 2 => 3, 3 => 2, 4 => 1 }[pos] || 0
    end

    # ===============================
    # MIXモード
    # ===============================
    def schedule_mixed_balanced!
      1.upto(@target_rounds) do |round_idx|
        round      = @event.rounds.create!(index: round_idx)
        used_round = Set.new
        made       = []

        loop do
          pool = @members
                   .select { |m| available_on_round?(m, round_idx) }
                   .reject { |m| used_round.include?(m.id) }
                   .sort_by { |m| [@played_counts[m.id], -fine_skill(m), m.id] }
          break if pool.size < 4

          quad = pool.first(4)
          p1, p2 = best_pairing_for_quad(quad, nil)
          made << [p1, p2]
          mark_used!(quad, used_round)
          break if made.size >= @courts
        end

        made.sort_by! { |p1, p2| -match_strength(p1, p2) }
        court_no = 1
        made.each do |p1, p2|
          break if court_no > @courts
          create_match!(round, court_no, p1, p2)
          court_no += 1
        end
      end
    end

    # ===============================
    # ペア選定ロジック
    # ===============================
    def pick_quad_for_gender_and_band(group, desired_band, used_round)
      pool = group.reject { |m| used_round.include?(m.id) }
      return [] if pool.size < 4

      sorted = pool.sort_by do |m|
        [
          (band_of(m) - desired_band).abs,
          @played_counts[m.id],
          -fine_skill(m),
          m.id
        ]
      end

      sorted.first(4)
    end

    def best_pairing_for_quad(quad, desired_band)
      a, b, c, d = quad
      candidates = [
        [[a, b], [c, d]],
        [[a, c], [b, d]],
        [[a, d], [b, c]],
      ]

      scored = candidates.filter_map do |p1, p2|
        next if ng_pair?(p1[0], p1[1]) || ng_pair?(p2[0], p2[1]) || ng_opponent?(p1, p2)

        p1_gap = (fine_skill(p1[0]) - fine_skill(p1[1])).abs
        p2_gap = (fine_skill(p2[0]) - fine_skill(p2[1])).abs
        dev = 0
        if desired_band
          avg1 = (fine_skill(p1[0]) + fine_skill(p1[1])) / 2.0
          avg2 = (fine_skill(p2[0]) + fine_skill(p2[1])) / 2.0
          target = representative_score_for_band(desired_band)
          dev = (avg1 - target).abs + (avg2 - target).abs
        end
        [p1, p2, p1_gap + p2_gap + dev]
      end

      scored = candidates.map { |p1, p2| [p1, p2, (fine_skill(p1[0]) - fine_skill(p1[1])).abs + (fine_skill(p2[0]) - fine_skill(p2[1])).abs] } if scored.empty?
      best = scored.min_by { |_p1, _p2, s| s }
      [best[0], best[1]]
    end

    def match_strength(p1, p2) = pair_strength(p1) + pair_strength(p2)
    def pair_strength(pair)    = pair.sum { |m| fine_skill(m) }

    def representative_score_for_band(band)
      { 4 => 100, 3 => 70, 2 => 40, 1 => 10 }[band] || 0
    end

    def fine_skill(member)
      if defined?(Member) && Member.respond_to?(:skill_levels) && member.respond_to?(:skill_level)
        val = Member.skill_levels[member.skill_level] rescue nil
        return val.to_i if val
      end

      key  = member.respond_to?(:skill_level) ? member.skill_level.to_s.strip : ""
      norm = key.upcase.gsub("-", "_")
      table = {
        "A_PLUS" => 10, "A" => 9, "A_MINUS" => 8,
        "B_PLUS" => 7,  "B" => 6, "B_MINUS" => 5,
        "C_PLUS" => 4,  "C" => 3, "C_MINUS" => 2,
        "D_PLUS" => 1,  "D" => 0
      }
      table[norm] || case
                     when norm.include?("ADVANCED") then 9
                     when norm.include?("MIDDLE")   then 6
                     when norm.include?("BEGINNER") then 3
                     else 0
                     end
    end

    def band_of(member)
      case fine_skill(member)
      when 8..10 then 4
      when 5..7  then 3
      when 2..4  then 2
      else 1
      end
    end

    def gender_of(member)
      g = (member.respond_to?(:gender) && member.gender).to_s.strip.downcase
      return :male   if %w[male m 男 男子].include?(g)
      return :female if %w[female f 女 女子].include?(g)
      :unknown
    end

    def create_match!(round, court_number, pair1, pair2)
      round.matches.create!(
        court_number:  court_number,
        pair1_member1: pair1[0],
        pair1_member2: pair1[1],
        pair2_member1: pair2[0],
        pair2_member2: pair2[1]
      )
    end

    def mark_used!(members4, used_round)
      members4.each do |m|
        used_round << m.id
        @played_counts[m.id] += 1
      end
    end

    def ng_pair?(a, b)
      return false unless defined?(MemberRelation) && MemberRelation.respond_to?(:ng_between?)
      MemberRelation.ng_between?(a.id, b.id, :avoid_pair)
    end

    def ng_opponent?(pair1, pair2)
      return false unless defined?(MemberRelation) && MemberRelation.respond_to?(:ng_between?)
      pair1.any? { |x| pair2.any? { |y| MemberRelation.ng_between?(x.id, y.id, :avoid_opponent) } }
    end
  end
end
