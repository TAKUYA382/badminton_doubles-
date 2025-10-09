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
      @members       = pick_base_members(event)          # 「不参加以外」のメンバー
      @target_rounds = (target_rounds.presence || 1).to_i
      @mode          = mode.to_s
      @ep_cache      = {}                                # member_id => EventParticipant
    end

    def call
      @played_counts = Hash.new(0)

      return Result.new(false, "このイベントの参加者（不参加以外）が4名以上必要です") if @members.size < 4
      return Result.new(false, "コート数が1以上必要です") if @courts < 1

      ActiveRecord::Base.transaction do
        # 既存の編成は作り直し
        @event.rounds.destroy_all

        case @mode
        when "split" then schedule_split_ranked!
        when "mixed" then schedule_mixed_balanced!
        else
          raise ArgumentError, "未知のメイキングモード: #{@mode}"
        end
      end

      Result.new(true, nil)
    rescue => e
      # 例外は握り込んで Result として返す（コントローラ側でログ推奨）
      Result.new(false, e.message)
    end

    private

    # ===============================
    # 参加者抽出：「不参加」以外（attending/late/early_leave/undecided）
    # ===============================
    def pick_base_members(event)
      eps = event.event_participants
                 .where.not(status: :absent)
                 .includes(:member)

      eps.each do |ep|
        next unless ep.member
        @ep_cache[ep.member_id] = ep
      end

      eps.map(&:member).compact.uniq
    end

    # ===============================
    # ラウンド在席判定（1-indexed）
    # - arrival_round が nil なら最初から在席
    # - leave_round / departure_round が nil なら最後まで在席
    # - arrival / leave といった別名にもゆるく対応
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
      arrived && not_left
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
        made       = [] # [[:male/:female, desired_band(4..1), p1, p2], ...]

        # 今ラウンド在席
        avail   = @members.select { |m| available_on_round?(m, round_idx) }
        males   = avail.select { |m| gender_of(m) == :male }
        females = avail.select { |m| gender_of(m) == :female }

        # 男子：A(4)→B(3)→C(2)→D(1)
        (1..male_courts).each do |pos|
          desired = band_for_position(pos)
          quad    = pick_quad_for_gender_and_band(males, desired, used_round)
          break if quad.size < 4
          p1, p2 = best_pairing_for_quad(quad, desired)
          made << [:male, desired, p1, p2]
          mark_used!(quad, used_round)
        end

        # 女子：同様
        (1..female_courts).each do |pos|
          desired = band_for_position(pos)
          quad    = pick_quad_for_gender_and_band(females, desired, used_round)
          break if quad.size < 4
          p1, p2 = best_pairing_for_quad(quad, desired)
          made << [:female, desired, p1, p2]
          mark_used!(quad, used_round)
        end

        # 作れた分だけ強い順（同帯なら試合強度降順）で 1..@courts に採番
        male_made   = made.select { |sex, *_| sex == :male }
                          .sort_by { |_sex, band, p1, p2| [-band, -match_strength(p1, p2)] }
        female_made = made.select { |sex, *_| sex == :female }
                          .sort_by { |_sex, band, p1, p2| [-band, -match_strength(p1, p2)] }

        court_no = 1
        male_made.each do |_sex, _band, p1, p2|
          break if court_no > @courts
          create_match!(round, court_no, p1, p2)
          court_no += 1
        end
        female_made.each do |_sex, _band, p1, p2|
          break if court_no > @courts
          create_match!(round, court_no, p1, p2)
          court_no += 1
        end
      end
    end

    # コート位置→帯（A=4, B=3, C=2, D=1）
    def band_for_position(pos)
      case pos
      when 1 then 4
      when 2 then 3
      when 3 then 2
      when 4 then 1
      else 0
      end
    end

    # ===============================
    # MIX：出場回数の少なさ優先で 4 人ずつ拾って作成
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
    # 選手選定・スコア
    # ===============================
    def pick_quad_for_gender_and_band(group, desired_band, used_round)
      pool = group.reject { |m| used_round.include?(m.id) }
      return [] if pool.size < 4

      sorted = pool.sort_by do |m|
        [
          (band_of(m) - desired_band).abs, # 目標帯からの距離
          @played_counts[m.id],            # 出場回数の少なさ
          -fine_skill(m),                  # 細かい強さ（降順）
          m.id
        ]
      end

      pick = sorted.first(4)
      i = 4
      while pick.size < 4 && i < sorted.size
        pick << sorted[i]
        i += 1
      end
      pick
    end

    # 4人を2ペアに分ける：ペア内差 +（必要なら）帯ターゲットからのズレ を最小化
    def best_pairing_for_quad(quad, desired_band)
      a, b, c, d = quad
      candidates = [
        [[a, b], [c, d]],
        [[a, c], [b, d]],
        [[a, d], [b, c]],
      ]

      scored = candidates.map do |p1, p2|
        next if ng_pair?(p1[0], p1[1]) || ng_pair?(p2[0], p2[1]) || ng_opponent?(p1, p2)

        p1_gap = (fine_skill(p1[0]) - fine_skill(p1[1])).abs
        p2_gap = (fine_skill(p2[0]) - fine_skill(p2[1])).abs

        dev = 0
        if desired_band
          avg1   = (fine_skill(p1[0]) + fine_skill(p1[1])) / 2.0
          avg2   = (fine_skill(p2[0]) + fine_skill(p2[1])) / 2.0
          target = representative_score_for_band(desired_band)
          dev    = (avg1 - target).abs + (avg2 - target).abs
        end

        [p1, p2, p1_gap + p2_gap + dev]
      end.compact

      # すべて NG ならペア差最小で決定
      if scored.empty?
        scored = candidates.map do |p1, p2|
          p1_gap = (fine_skill(p1[0]) - fine_skill(p1[1])).abs
          p2_gap = (fine_skill(p2[0]) - fine_skill(p2[1])).abs
          [p1, p2, p1_gap + p2_gap]
        end
      end

      best = scored.min_by { |_p1, _p2, s| s }
      [best[0], best[1]]
    end

    # コート並べ替え用の“試合強度”
    def match_strength(p1, p2) = pair_strength(p1) + pair_strength(p2)
    def pair_strength(pair)    = pair.sum { |m| fine_skill(m) }

    # 帯の代表値（吸着用）
    def representative_score_for_band(band)
      case band
      when 4 then 100 # A帯
      when 3 then 70  # B帯
      when 2 then 40  # C帯
      when 1 then 10  # D帯
      else 0
      end
    end

    # ===============================
    # 属性 → 数値化
    # ===============================
    def fine_skill(member)
      if defined?(Member) && Member.respond_to?(:skill_levels) && member.respond_to?(:skill_level)
        val = Member.skill_levels[member.skill_level] rescue nil
        return val.to_i if val
      end

      key  = member.respond_to?(:skill_level) ? member.skill_level.to_s.strip : ""
      norm = key.upcase.gsub("-", "_")
      table = {
        "A_PLUS" => 10, "A" => 9,  "A_MINUS" => 8,
        "B_PLUS" => 7,  "B" => 6,  "B_MINUS" => 5,
        "C_PLUS" => 4,  "C" => 3,  "C_MINUS" => 2,
        "D_PLUS" => 1,  "D" => 0
      }
      return table[norm] if table.key?(norm)

      # ゆるい表記対応
      return 9 if norm.include?("ADVANCED")
      return 6 if norm.include?("MIDDLE")
      return 3 if norm.include?("BEGINNER")
      0
    end

    # A/B/C/D の 4 帯へ圧縮（A=4, B=3, C=2, D=1）
    def band_of(member)
      s = fine_skill(member)
      case s
      when 8..10 then 4 # A帯（A-,A,A+）
      when 5..7  then 3 # B帯
      when 2..4  then 2 # C帯
      else            1 # D帯
      end
    end

    # gender を :male / :female / :unknown に正規化（日本語も許容）
    def gender_of(member)
      g = (member.respond_to?(:gender) && member.gender).to_s.strip.downcase
      return :male   if %w[male m 男 男子].include?(g)
      return :female if %w[female f 女 女子].include?(g)
      :unknown
    end

    # ===============================
    # 生成・カウント
    # ===============================
    def create_match!(round, court_number, pair1, pair2)
      round.matches.create!(
        court_number:  court_number,
        pair1_member1: pair1[0], pair1_member2: pair1[1],
        pair2_member1: pair2[0], pair2_member2: pair2[1]
      )
    end

    def mark_used!(members4, used_round)
      members4.each do |m|
        used_round << m.id
        @played_counts[m.id] += 1
      end
    end

    # ===============================
    # NG helpers（定義が無い環境でも落ちないようガード）
    # ===============================
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
