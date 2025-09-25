# app/services/scheduling/auto_schedule.rb
# frozen_string_literal: true

require "set"

module Scheduling
  class Result < Struct.new(:success?, :error_message); end

  class AutoSchedule
    # mode: "split"（男女別）, "mixed"（MIX）
    # target_rounds: 生成するラウンド数（nil なら 1）
    def initialize(event, target_rounds: nil, mode: "split")
      @event         = event
      @courts        = event.court_count.to_i
      @members       = pick_attending_members(event) # このイベントに「参加」のメンバーだけ
      @target_rounds = (target_rounds.presence || 1).to_i
      @mode          = mode.to_s
    end

    def call
      @played_counts = Hash.new(0)
      return Result.new(false, "このイベントの参加者（参加）が4名以上必要です") if @members.size < 4
      return Result.new(false, "コート数が1以上必要です") if @courts < 1

      ActiveRecord::Base.transaction do
        # 既存の編成は作り直し
        @event.rounds.destroy_all

        case @mode
        when "split"  then schedule_split_ranked!   # ★ご要望の“男女別 + コートでランク固定”
        when "mixed"  then schedule_mixed_balanced!
        else
          raise ArgumentError, "未知のメイキングモード: #{@mode}"
        end
      end

      Result.new(true, nil)
    rescue => e
      Result.new(false, e.message)
    end

    private

    # =====================================
    # 参加者の抽出：このイベントで「参加」だけ
    # Event has_many :event_participants, each belongs_to :member と想定
    # =====================================
    def pick_attending_members(event)
      event.event_participants
           .where(status: :attending)
           .includes(:member)
           .map(&:member)
           .compact
           .uniq
    end

    # =====================================
    # ★ 男女別：1..男コート(A,B,C,D..), 続き..女コート(A,B,C,D..)
    # ・男子は 1 コートから A,B,C,D …
    # ・女子は 男コートの続きから A,B,C,D …
    # ・指定ランクが4人に満たない場合は「目標ランクに近い順」→「強い順」で補完
    # ・同一ラウンド内で重複出場しない
    # ・ペア/対戦は“差が小さい”&“目標ランクに近い”組み合わせを優先
    # =====================================
    def schedule_split_ranked!
      male_courts   = (@courts / 2.0).ceil
      female_courts = @courts - male_courts

      males   = @members.select { |m| gender_of(m) == :male }
      females = @members.select { |m| gender_of(m) == :female }
      raise "男子または女子の人数が足りません（各4名以上）" if males.size < 4 || females.size < 4

      1.upto(@target_rounds) do |round_idx|
        round      = @event.rounds.create!(index: round_idx)
        used_round = Set.new

        # --- 男子（コート 1..male_courts） ---
        1.upto(male_courts) do |pos|
          desired = desired_rank_for_position(pos) # 1=>A, 2=>B, 3=>C, 4=>D, それ以降は E=0
          quad    = pick_quad_for_gender_and_rank(males, desired, used_round)
          next if quad.size < 4
          p1, p2 = best_pairing_for_quad(quad, desired)
          create_match!(round, pos, p1, p2)
          mark_used!(quad, used_round)
        end

        # --- 女子（コート male_courts+1..@courts） ---
        1.upto(female_courts) do |offset|
          court_no = male_courts + offset
          desired  = desired_rank_for_position(offset) # 女子も 1=>A,2=>B,…
          quad     = pick_quad_for_gender_and_rank(females, desired, used_round)
          next if quad.size < 4
          p1, p2 = best_pairing_for_quad(quad, desired)
          create_match!(round, court_no, p1, p2)
          mark_used!(quad, used_round)
        end
      end
    end

    # 位置→希望ランク（数値）  A=4, B=3, C=2, D=1, それ以降 0
    def desired_rank_for_position(pos)
      case pos
      when 1 then 4
      when 2 then 3
      when 3 then 2
      when 4 then 1
      else         0
      end
    end

    # 指定性別グループから“同ラウンド未使用”の 4 人を、希望ランクに“近い順”→出場回数少→強い順で選ぶ
    # 不足する場合は自動で近いランクから補完（結果的に「上のランクから順に」も満たす）
    def pick_quad_for_gender_and_rank(group, desired_rank, used_round)
      pool = group.reject { |m| used_round.include?(m.id) }
      return [] if pool.size < 4

      # 目標に近い順（差の絶対値）、次に出場回数が少ない、最後に強い順
      sorted = pool.sort_by { |m| [ (rank_value(m) - desired_rank).abs, @played_counts[m.id], -rank_value(m), m.id ] }
      # まず 4 人候補
      pick = sorted.first(4)

      # NG などで弾かれて 4 未満になったら、順に追加して満たす
      i = 4
      while pick.size < 4 && i < sorted.size
        pick << sorted[i]
        i += 1
      end
      pick
    end

    # 与えられた4人を「ペア内の差 + 目標ランクからのズレ」が最小になる 2 ペアに分割
    def best_pairing_for_quad(quad, desired_rank)
      a, b, c, d = quad
      candidates = [
        [[a, b], [c, d]],
        [[a, c], [b, d]],
        [[a, d], [b, c]],
      ]

      scored = candidates.map do |p1, p2|
        # NGチェック（定義が無い環境でも落ちないようガード）
        next if ng_pair?(p1[0], p1[1]) || ng_pair?(p2[0], p2[1]) || ng_opponent?(p1, p2)

        p1_gap = (rank_value(p1[0]) - rank_value(p1[1])).abs
        p2_gap = (rank_value(p2[0]) - rank_value(p2[1])).abs

        dev = 0
        if desired_rank
          avg1 = (rank_value(p1[0]) + rank_value(p1[1])) / 2.0
          avg2 = (rank_value(p2[0]) + rank_value(p2[1])) / 2.0
          dev  = (avg1 - desired_rank).abs + (avg2 - desired_rank).abs
        end

        score = p1_gap + p2_gap + dev
        [p1, p2, score]
      end.compact

      # すべて NG なら、差だけで最小の組み合わせを採用
      if scored.empty?
        scored = candidates.map do |p1, p2|
          p1_gap = (rank_value(p1[0]) - rank_value(p1[1])).abs
          p2_gap = (rank_value(p2[0]) - rank_value(p2[1])).abs
          [p1, p2, p1_gap + p2_gap]
        end
      end

      best = scored.min_by { |_p1, _p2, s| s }
      [best[0], best[1]]
    end

    # =====================================
    # MIX：全体バランス（参加回数が均等、強すぎる偏りを抑える）
    # ※ご要望の主対象は split なので、MIX は従来通りのバランス寄り
    # =====================================
    def schedule_mixed_balanced!
      1.upto(@target_rounds) do |round_idx|
        round      = @event.rounds.create!(index: round_idx)
        used_round = Set.new

        1.upto(@courts) do |court_no|
          pool = @members.reject { |m| used_round.include?(m.id) }
                         .sort_by { |m| [@played_counts[m.id], -rank_value(m), m.id] }
          break if pool.size < 4

          quad = pool.first(4)
          p1, p2 = best_pairing_for_quad(quad, nil)
          create_match!(round, court_no, p1, p2)
          mark_used!(quad, used_round)
        end
      end
    end

    # =====================================
    # 共通ユーティリティ
    # =====================================

    # 対戦を1件作成
    def create_match!(round, court_number, pair1, pair2)
      round.matches.create!(
        court_number:    court_number,
        pair1_member1:   pair1[0],
        pair1_member2:   pair1[1],
        pair2_member1:   pair2[0],
        pair2_member2:   pair2[1]
      )
    end

    # ラウンド内使用 & 出場回数カウント
    def mark_used!(members4, used_round)
      members4.each do |m|
        used_round << m.id
        @played_counts[m.id] += 1
      end
    end

    # ランク値：A=4, B=3, C=2, D=1, その他=0
    # skill_level に "A/B/C/D" を推奨（他に "advanced/middle/beginner" も簡易対応）
    def rank_value(member)
      raw = (member.respond_to?(:skill_level) && member.skill_level).to_s.strip.downcase
      case raw
      when "a"        then 4
      when "b"        then 3
      when "c"        then 2
      when "d"        then 1
      when "advanced" then 4
      when "middle"   then 3
      when "beginner" then 2
      else 0
      end
    end

    # gender を :male / :female 正規化（日本語も許容）
    def gender_of(member)
      g = (member.respond_to?(:gender) && member.gender).to_s.strip.downcase
      return :male   if %w[male m 男 男子].include?(g)
      return :female if %w[female f 女 女子].include?(g)
      :unknown
    end

    # NG 関係（定義が無い環境でも落ちないようにガード）
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