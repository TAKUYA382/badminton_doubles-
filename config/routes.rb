Rails.application.routes.draw do
  # 管理者ログイン用（Deviseで管理者認証）
  devise_for :admins, path: "admin", skip: [:registrations]

  namespace :admin do
    # 管理画面のトップページをイベント一覧に設定
    root "events#index"

    # メンバー管理
    resources :members

    # イベント管理
    resources :events do
      # ================================
      # ▼ 出欠管理をイベント配下にネスト
      # URL例: /admin/events/:event_id/attendances
      # コントローラは EventParticipantsController を使用
      # ================================
      resources :attendances,
                controller: "event_participants", # ★ ここでコントローラを指定
                only: [:index, :create, :update, :destroy]

      # 自動スケジュール生成や公開/非公開の切り替え
      post  :auto_schedule, on: :member
      patch :publish,       on: :member
      patch :unpublish,     on: :member

      # スロット編集（手動のクリア／差し替え）
      patch :update_slot,   on: :member

      # 差し替え候補メンバー取得（必要なら）
      get :available_members, on: :member

      # ▼ 参加者一括ペースト入力（コピペ登録）
      member do
        get  :paste_participants,          to: "event_participants_imports#paste_form"
        post :paste_participants_preview,  to: "event_participants_imports#preview"
        post :paste_participants_commit,   to: "event_participants_imports#commit"
      end
    end

    # 対人NG設定
    resources :member_relations, only: [:create, :destroy]

    # マッチ編集系（DnD用の入れ替えなど）
    resources :matches, only: [] do
      # 並び替え（必要なら）
      patch :reorder, on: :collection
      # ドラッグ＆ドロップで2スロットを入れ替える
      patch :swap,    on: :collection
      # 単一スロット操作
      patch :clear_slot,      on: :member
      patch :replace_member,  on: :member
    end
  end

  # 公開側（誰でも閲覧可能）
  resources :events, only: [:index, :show]

  # サービス内容ページ
  get "/service", to: "pages#service", as: :service

  # ルートは公開側のイベント一覧
  root "events#index"
end