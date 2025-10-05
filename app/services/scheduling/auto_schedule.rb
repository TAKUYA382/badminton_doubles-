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
        when "split" then schedule_split_ranked!
        when "mixed" then schedule_mixed_balanced!
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
    # 男女別：男子→女子の順に“作れたカード”を積んでから連番採番
    # 男子は 1 コートから強→弱、女子は続きのコートで強→弱
    # 強さ：A帯→B帯→C帯→D帯（A帯は A+,A,A- を含む）
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

        made = [] # [[:male/:female, desired_band(4..1), pair1, pair2], ...]

        # --- 男子：A(4)→B(3)→C(2)→D(1) 帯で male_courts 枚を目標に順次作る
        (1..male_courts).each do |pos|
          desired_band = band_for_position(pos)
          quad = pick_quad_for_gender_and_band(males, desired_band, used_round)
          break if quad.size < 4
          p1, p2 = best_pairing_for_quad(quad, desired_band)
          made << [:male, desired_band, p1, p2]
          mark_used!(quad, used_round)
        end

        # --- 女子：男子の続き。1..female_courts を A→B→C→D に対応
        (1..female_courts).each do |pos|
          desired_band = band_for_position(pos)
          quad = pick_quad_for_gender_and_band(females, desired_band, used_round)
          break if quad.size < 4
          p1, p2 = best_pairing_for_quad(quad, desired_band)
          made << [:female, desired_band, p1, p2]
          mark_used!(quad, used_round)
        end

        # ---- ここが重要：作れたカードだけを強い順に並べ、連番で採番（欠番なし）
        male_made   = made.select { |sex, *_| sex == :male }
                          .sort_by { |_sex, band, p1, p2| [-band, -match_strength(p1, p2)] }
        female_made = made.select { |sex, *_| sex == :female }
                          .sort_by { |_sex, band, p1, p2| [-band, -match_strength(p1, p2)] }

        court_no = 1
        male_made.each do |_sex, _band, p1, p2|
          create_match!(round, court_no, p1, p2)
          court_no += 1
          break if court_no > @courts
        end
        female_made.each do |_sex, _band, p1, p2|
          break if court_no > @courts
          create_match!(round, court_no, p1, p2)
          court_no += 1
        end
      end
    end

    # コート位置→希望バンド（A=4, B=3, C=2, D=1, それ以外=0）
    def band_for_position(pos)
      case pos
      when 1 then 4
      when 2 then 3
      when 3 then 2
      when 4 then 1
      else 0
      end
    end

    # =====================================
    # MIX：回数が少ない順に 4 人拾って作れるだけ作る → 強い順に 1..@courts 採番
    # =====================================
    def schedule_mixed_balanced!
      1.upto(@target_rounds) do |round_idx|
        round      = @event.rounds.create!(index: round_idx)
        used_round = Set.new
        made       = []

        # まず作れるだけカードを作る（同一ラウンド内で重複出場なし）
        loop do
          pool = @members.reject { |m| used_round.include?(m.id) }
                         .sort_by { |m| [@played_counts[m.id], -fine_skill(m), m.id] }
          break if pool.size < 4
          quad = pool.first(4)
          p1, p2 = best_pairing_for_quad(quad, nil)
          made << [p1, p2]
          mark_used!(quad, used_round)
          break if made.size >= @courts
        end

        # 強い順に 1..@courts で採番（欠番なし）
        made.sort_by! { |p1, p2| -match_strength(p1, p2) }
        court_no = 1
        made.each do |p1, p2|
          create_match!(round, court_no, p1, p2)
          court_no += 1
          break if court_no > @courts
        end
      end
    end

    # =====================================
    # 選手選定・スコア
    # =====================================

    # 指定性別から“同ラウンド未使用”の4人を、希望バンドに近い順 → 出場回数少 → 細かいスコア強 → id
    # 希望に満たない場合は自動補完（近い帯から）
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

      pick = sorted.first(4)
      i = 4
      while pick.size < 4 && i < sorted.size
        pick << sorted[i]
        i += 1
      end
      pick
    end

    # 4人を 2 ペアに分ける。ペア内差 +（必要なら）希望帯からのズレ を最小に
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

      # すべて NG なら、差だけで最小の組み合わせ
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
    def match_strength(p1, p2)
      pair_strength(p1) + pair_strength(p2)
    end

    def pair_strength(pair)
      pair.sum { |m| fine_skill(m) }
    end

    # 帯（A..D）の代表値（強さ吸着用）
    def representative_score_for_band(band)
      case band
      when 4 then 100 # A 帯
      when 3 then 70  # B 帯
      when 2 then 40  # C 帯
      when 1 then 10  # D 帯
      else 0
      end
    end

    # =====================================
    # 属性・カウント
    # =====================================

    # “細かい段位”の数値スコア（大きいほど強い）
    # - enum を使っていれば Member.skill_levels[member.skill_level] を優先
    # - 文字列でも A_plus/A/A_minus/…/D を解釈
    def fine_skill(member)
      # enum（例: { "A_plus"=>10, "A"=>9, "A_minus"=>8, ... "D"=>0 }）
      if defined?(Member) && Member.respond_to?(:skill_levels) && member.respond_to?(:skill_level)
        val = Member.skill_levels[member.skill_level] rescue nil
        return val.to_i if val
      end

      # 文字列パターンにも対応
      key = member.respond_to?(:skill_level) ? member.skill_level.to_s.strip : ""

      # 正規化（全て大文字・アンダースコア化）
      norm = key.upcase.gsub("-", "_")

      table = {
        "A_PLUS" => 10, "A" => 9,  "A_MINUS" => 8,
        "B_PLUS" => 7,  "B" => 6,  "B_MINUS" => 5,
        "C_PLUS" => 4,  "C" => 3,  "C_MINUS" => 2,
        "D_PLUS" => 1,  "D" => 0
      }
      return table[norm] if table.key?(norm)

      # 旧表記のゆるい対応
      return 9 if norm.include?("ADVANCED")
      return 6 if norm.include?("MIDDLE")
      return 3 if norm.include?("BEGINNER")

      0
    end

    # A/B/C/D の 4 帯へ圧縮（A=4, B=3, C=2, D=1）
    # ※ A- も A帯として扱う（バグ修正）
    def band_of(member)
      s = fine_skill(member)
      case s
      when 8..10 then 4 # A帯（A-,A,A+）
      when 5..7  then 3 # B帯（B-,B,B+）
      when 2..4  then 2 # C帯（C-,C,C+）
      else            1 # D帯（D,D+ 他）
      end
    end

    # gender を :male / :female 正規化（日本語も許容）
    def gender_of(member)
      g = (member.respond_to?(:gender) && member.gender).to_s.strip.downcase
      return :male   if %w[male m 男 男子].include?(g)
      return :female if %w[female f 女 女子].include?(g)
      :unknown
    end

    # =====================================
    # 生成・カウント
    # =====================================

    def create_match!(round, court_number, pair1, pair2)
      round.matches.create!(
        court_number:  court_number,
        pair1_member1: pair1[0], pair1_member2: pair1[1],
        pair2_member1: pair2[0], pair2_member2: pair2[1]
      )
    end

    # ラウンド内使用 & 出場回数カウント
    def mark_used!(members4, used_round)
      members4.each do |m|
        used_round << m.id
        @played_counts[m.id] += 1
      end
    end

    # =====================================
    # NG helpers（定義が無い環境でも落ちないようガード）
    # =====================================
    def ng_pair?(a, b)
      return false unless defined?(MemberRelation) && MemberRelation.respond_to?(:ng_between?)
      MemberRelation.ng_between?(a.id, b.id, :avoid_pair)
    end

    def ng_opponent?(pair1, pair2)