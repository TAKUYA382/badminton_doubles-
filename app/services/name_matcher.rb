# app/services/name_matcher.rb
# 名前と出欠ステータスをテキストから一括取り込みして、Memberにマッチングするサービスクラス
class NameMatcher
  # 各行のステータス判定用マップ
  LINE_STATUS_MAP = {
    "参加" => :attending,
    "未定" => :undecided,
    "欠席" => :absent
  }.freeze

  # scope: 照合対象となる Member の ActiveRecord::Relation（通常は Member.active）
  def initialize(scope: Member.active)
    @members = scope.to_a
    @index   = build_index(@members) # 正規化後の名前をキーにしたインデックス
  end

  # テキストを1行ずつ解析して配列化
  # 例:
  #   "山田太郎,参加" → { raw: "山田太郎,参加", name: "山田太郎", normalized: "ヤマダタロウ", status: :attending }
  #   "鈴木花子 欠席" → { raw: "鈴木花子 欠席", name: "鈴木花子", normalized: "スズキハナコ", status: :absent }
  def parse_lines(text)
    text.to_s.split(/\r?\n/).map(&:strip).reject(&:blank?).map do |line|
      name_part, status_part = parse_line(line)
      norm = normalize(name_part)
      {
        raw: line,
        name: name_part,
        normalized: norm,
        status: status_part
      }
    end
  end

  # プレビュー用：一致状況を判定
  # match: :unique（1件一致）, :none（未一致）, :ambiguous（複数候補）
  def preview(items)
    items.map do |it|
      matches = @index[it[:normalized]] || []
      case matches.size
      when 1
        it.merge(match: :unique, member: matches.first)
      when 0
        it.merge(match: :none, candidates: [])
      else
        it.merge(match: :ambiguous, candidates: matches)
      end
    end
  end

  # 一意にマッチした場合のみ Member を返す
  def find_unique(normalized)
    list = @index[normalized] || []
    list.size == 1 ? list.first : nil
  end

  private

  # 1行を分割して [名前, ステータスシンボル] を返す
  # 区切りはカンマ or 空白に対応
  def parse_line(line)
    # 例: "山田太郎 参加" / "山田太郎,参加"
    tokens = line.split(/[,\s]+/).reject(&:blank?)

    # 最後のトークンがLINE_STATUS_MAPにあれば、それをステータスとして扱う
    status_sym = LINE_STATUS_MAP[tokens.last] || :attending # 指定なければ参加扱い
    name =
      if LINE_STATUS_MAP.key?(tokens.last)
        tokens[0..-2].join("")
      else
        tokens.join("")
      end

    [name, status_sym]
  end

  # メンバー一覧を正規化した名前ごとにグループ化してインデックス化
  def build_index(members)
    members.group_by { |m| normalize(m.name) }
  end

  # 名前を比較可能な形に正規化
  # - 全角空白を半角に
  # - ひらがなをカタカナに
  # - 全角英数を半角に
  # - 空白や記号を除去
  def normalize(str)
    s = str.to_s
    s = s.tr("　", " ")                   # 全角空白 → 半角
    s = s.gsub(/[[:space:]]+/, "")        # 空白除去
    s = s.tr("ぁ-ゖ", "ァ-ヶ")            # ひらがな → カタカナ
    s = s.tr("０-９ａ-ｚＡ-Ｚ", "0-9a-zA-Z") # 全角英数字 → 半角
    s = s.gsub(/[()（）・\-‐ー\.\,]/, "")   # 記号削除
    s
  end
end