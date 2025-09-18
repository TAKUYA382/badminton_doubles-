# app/controllers/admin/members_controller.rb
class Admin::MembersController < Admin::BaseController
  # ビューから呼べるようにヘルパー公開（▲▼トグルで使用）
  helper_method :sort_direction_toggle

  # ================================
  # メンバー一覧
  # ================================
  def index
    @q = params[:q].to_s.strip

    # 並べ替え許可カラム
    allowed        = %w[reading name name_kana grade skill_level gender id]
    sort_column    = allowed.include?(params[:sort]) ? params[:sort] : 'reading'
    sort_direction = %w[asc desc].include?(params[:direction]) ? params[:direction] : 'asc'

    scope = Member.name_like(@q)

    @members =
      case sort_column
      when 'reading'
        # 読み順（かな→無ければ name）
        scope.order(Arel.sql("COALESCE(NULLIF(name_kana, ''), name) #{sort_direction.upcase}"))
      when 'name_kana'
        scope.order("name_kana #{sort_direction}")
      else
        scope.order("#{sort_column} #{sort_direction}")
      end
  end

  # ================================
  # 新規作成
  # ================================
  def new
    @member = Member.new
  end

  def create
    @member = Member.new(member_params)
    if @member.save
      redirect_to admin_members_path, notice: 'メンバーを登録しました。'
    else
      render :new, status: :unprocessable_entity
    end
  end

  # ================================
  # 編集・更新
  # ================================
  def edit
    @member = Member.find(params[:id])
  end

  def update
    @member = Member.find(params[:id])
    if @member.update(member_params)
      redirect_to admin_members_path, notice: 'メンバー情報を更新しました。'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  # ================================
  # 削除
  # ================================
  def destroy
    @member = Member.find(params[:id])
    @member.destroy
    redirect_to admin_members_path, notice: 'メンバーを削除しました。'
  end

  private

  # Strong Parameters（読み：name_kana を追加）
  def member_params
    params.require(:member).permit(:name, :name_kana, :grade, :gender, :skill_level)
  end

  # 並べ替えリンク用：クリックするたび asc ⇔ desc を切り替え
  def sort_direction_toggle(column)
    if params[:sort] == column && params[:direction] == 'asc'
      'desc'
    else
      'asc'
    end
  end
end