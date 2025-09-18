# app/services/scheduling/auto_schedule.rb
require "set"

module Scheduling
  class Result < Struct.new(:success?, :error_message); end

  class AutoSchedule
    def initialize(event, target_rounds: nil, mode: "split")
      @event         = event
      @courts        = event.court_count.to_i
      @members       = pick_attending_members(event) # このイベントの「参加」だけ
      @target_rounds = target_rounds
      @mode          = mode
    end

    def call
      @played_counts = Hash.new(0)
      return Result.new(false, "このイベントの参加者（参加）が4名以上必要です") if @members.size < 4

      ActiveRecord::Base.transaction do
        @event.rounds.destroy_all

        case @mode
        when "split" then schedule_split
        when "mixed" then schedule_mixed
        else
          raise ArgumentError, "未知のメイキングモード: #{@mode}"
        end
      end

      Result.new(true, nil)
    rescue => e
      Result.new(false, e.message)
    end

    private

    # ===== このイベントの「参加」だけを対象化 =====
    def pick_attending_members(event)
      event.event_participants
           .where(status: :attending)
           .includes(:member)
           .map(&:member)
           .compact
           .uniq
    end

    # ========================
    # 男女別
    # 男子 → コート1から順に強い試合
    # 女子 → 残りコートに順に強い試合
    # ========================
    def schedule_split
      males   = @members.select(&:male?)
      females = @members.select(&:female?)
      raise "男子または女子の人数が足りません（各4名以上）" if males.size < 4 || females.size < 4

      rounds        = @target_rounds || 1
      male_courts   = (@courts / 2.0).ceil
      female_courts = @courts - male_courts

      (1..rounds).each do |idx|
        round    = @event.rounds.create!(index: idx)
        used_ids = Set.new

        # --- 男子 ---
        male_pairs_needed = male_courts * 2
        male_pairs        = build_pairs_rotating(males, male_pairs_needed, used_ids)
        male_pairings     = take_pairings(male_pairs, male_courts)

        # 強い順にソートしてコート1から順に配置
        male_sorted = male_pairings.sort_by { |(p1, p2)| -match_power(p1, p2) }
        male_sorted.each_with_index do |(p1, p2), i|
          court_no = i + 1
          create_match!(round, court_no, p1, p2)
        end

        # --- 女子 ---
        female_pairs_needed = female_courts * 2
        female_pairs        = build_pairs_rotating(females, female_pairs_needed, used_ids)
        female_pairings     = take_pairings(female_pairs, female_courts)

        female_sorted = female_pairings.sort_by { |(p1, p2)| -match_power(p1, p2) }
        female_sorted.each_with_index do |(p1, p2), i|
          court_no = male_courts + i + 1
          create_match!(round, court_no, p1, p2)
        end
      end
    end

    # ========================
    # MIX
    # 全試合を強い順に並べてコート1から順に配置
    # ========================
    def schedule_mixed
      rounds = @target_rounds || 1

      (1..rounds).each do |idx|
        round = @event.rounds.create!(index: idx)

        candidates = [] # [[pair1, pair2], ...]

        1.upto(@courts) do
          m_pool = sorted_pool.select(&:male?)
          f_pool = sorted_pool.select(&:female?)

          paired = nil
          if m_pool.size >= 2 && f_pool.size >= 2
            m1, m2 = m_pool.first(2)
            f1, f2 = f_pool.first(2)
            cands  = [
              [[m1, f1], [m2, f2]],
              [[m1, f2], [m2, f1]]
            ]
            p1, p2 = best_pairing_with_ng(cands)
            paired = [p1, p2] if p1 && p2
          end

          # 男女ペアが組めなければ同性ペアでフォールバック
          if paired.nil?
            fallback = same_gender_pairs_from(sorted_pool.first(4))
            paired   = fallback if fallback
          end

          break unless paired
          candidates << paired
          (paired[0] + paired[1]).each { |m| @played_counts[m.id] += 1 }
        end

        # 強い順にソートして1コートから配置
        ordered = candidates.sort_by { |(p1, p2)| -match_power(p1, p2) }
        ordered.each_with_index do |(p1, p2), i|
          create_match!(round, i + 1, p1, p2)
        end
      end
    end

    # ------------------------
    # 強さ計算
    # enumが大きい値ほど強い前提（A+ > ... > D）
    # ------------------------
    def skill_score(member)
      member.read_attribute_before_type_cast(:skill_level).to_i
    end

    def pair_power(pair)
      pair.sum { |m| skill_score(m) }
    end

    def match_power(p1, p2)
      pair_power(p1) + pair_power(p2)
    end

    # ------------------------
    # ペア同士を試合にする
    # ------------------------
    def take_pairings(pairs, court_count)
      list = pairs.sort_by { |p| pair_avg_level(p) }.dup
      out  = []
      while out.size < court_count && list.size >= 2
        p1 = list.shift
        j  = list.each_with_index.min_by { |q, _i| (pair_avg_level(q) - pair_avg_level(p1)).abs }&.last
        break unless j
        p2 = list.delete_at(j)
        next if ng_pair?(p1[0], p1[1]) || ng_pair?(p2[0], p2[1]) || ng_opponent?(p1, p2)
        out << [p1, p2]
      end
      out
    end

    # ------------------------
    # 出場回数→IDで安定ソート
    # ------------------------
    def sorted_pool
      @members.sort_by { |m| [@played_counts[m.id], m.id] }
    end

    # NG考慮した最良ペア選び
    def best_pairing_with_ng(candidates)
      scored = candidates.map do |p1, p2|
        next if ng_pair?(p1[0], p1[1]) || ng_pair?(p2[0], p2[1]) || ng_opponent?(p1, p2)
        [p1, p2, pair_score(p1) + pair_score(p2)]
      end.compact
      return nil if scored.empty?
      best = scored.min_by { |_p1, _p2, s| s }
      [best[0], best[1]]
    end

    # スキル差ペナルティ
    def pair_score(pair)
      gap = (skill_score(pair[0]) - skill_score(pair[1])).abs
      gap <= 1 ? gap : 10
    end

    # 同性ペア（4人から2ペア）
    def same_gender_pairs_from(pool4)
      pool4 = Array(pool4).compact
      return nil if pool4.size < 4
      a, b, c, d = pool4
      cands = [
        [[a, b], [c, d]],
        [[a, c], [b, d]],
        [[a, d], [b, c]]
      ]
      scored = cands.map do |p1, p2|
        next if ng_pair?(p1[0], p1[1]) || ng_pair?(p2[0], p2[1]) || ng_opponent?(p1, p2)
        [p1, p2, pair_score(p1) + pair_score(p2)]
      end.compact
      return nil if scored.empty?
      best = scored.min_by { |_p1, _p2, s| s }
      [best[0], best[1]]
    end

    # 平均レベル
    def pair_avg_level(pair)
      pair.sum { |mem| skill_score(mem) } / 2.0
    end

    # ペア作成
    def build_pairs_rotating(pool, need_pairs, used_ids)
      cand = pool.reject { |m| used_ids.include?(m.id) }
                 .sort_by { |m| [@played_counts[m.id], skill_score(m), m.id] }
      pairs = []
      while pairs.size < need_pairs && cand.size >= 2
        a = cand.shift
        b_idx = cand.each_with_index
                   .select { |x, _i| (skill_score(a) - skill_score(x)).abs <= 1 }
                   .min_by  { |x, _i| (skill_score(a) - skill_score(x)).abs }&.last
        b_idx ||= cand.each_with_index.min_by { |x, _i| (skill_score(a) - skill_score(x)).abs }&.last
        break unless b_idx
        b = cand.delete_at(b_idx)
        next if ng_pair?(a, b)
        pairs << [a, b]
        used_ids << a.id << b.id
      end
      pairs
    end

    def create_match!(round, court_number, pair1, pair2)
      round.matches.create!(
        court_number: court_number,
        pair1_member1: pair1[0], pair1_member2: pair1[1],
        pair2_member1: pair2[0], pair2_member2: pair2[1]
      )
      (pair1 + pair2).each { |m| @played_counts[m.id] += 1 }
    end

    # NG helpers
    def ng_pair?(a, b)
      MemberRelation.ng_between?(a.id, b.id, :avoid_pair)
    end

    def ng_opponent?(pair1, pair2)
      pair1.any? { |x| pair2.any? { |y| MemberRelation.ng_between?(x.id, y.id, :avoid_opponent) } }
    end
  end
end