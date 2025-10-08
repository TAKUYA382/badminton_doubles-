# config/routes.rb
Rails.application.routes.draw do
  # 管理者ログイン（Devise）
  devise_for :admins, path: "admin", skip: [:registrations]

  namespace :admin do
    # 管理画面トップ = イベント一覧
    root "events#index"

    # メンバー管理
    resources :members

    # イベント管理
    resources :events do
      # 出欠管理（EventParticipantsController を利用）
      # 例: /admin/events/:event_id/attendances
      resources :attendances,
                controller: "event_participants",
                only: [:index, :create, :update, :destroy]

      # 自動編成・公開切替など
      post  :auto_schedule, on: :member   # POST  /admin/events/:id/auto_schedule
      patch :publish,       on: :member   # PATCH /admin/events/:id/publish
      patch :unpublish,     on: :member   # PATCH /admin/events/:id/unpublish

      # 手動スロット編集（単発API）
      patch :update_slot,   on: :member   # PATCH /admin/events/:id/update_slot

      # 差し替え候補取得（必要なら）
      get :available_members, on: :member # GET   /admin/events/:id/available_members

      # 参加者一括ペースト
      member do
        get  :paste_participants,         to: "event_participants_imports#paste_form"
        post :paste_participants_preview, to: "event_participants_imports#preview"
        post :paste_participants_commit,  to: "event_participants_imports#commit"
      end
    end

    # 対人NG設定
    resources :member_relations, only: [:create, :destroy]

    # マッチ編集系
    resources :matches, only: [] do
      # 既存：個別操作
      patch :reorder,        on: :collection   # 並び替え
      patch :swap,           on: :collection   # 2スロット入れ替え（DnD）
      patch :clear_slot,     on: :member       # 単一スロットクリア
      patch :replace_member, on: :member       # 単一スロット差し替え

      # ★追加：まとめて更新（バッファ送信）
      # PATCH /admin/matches/bulk_update
      patch :bulk_update,    on: :collection
    end
  end

  # 公開側
  resources :events, only: [:index, :show]

  # サービス内容ページ
  get "/service", to: "pages#service", as: :service

  # ルート（公開側イベント一覧）
  root "events#index"
end