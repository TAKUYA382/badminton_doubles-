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
      resources :attendances,
                controller: "event_participants",
                only: [:index, :create, :update, :destroy]

      # 自動編成・公開切替
      post  :auto_schedule, on: :member
      patch :publish,       on: :member
      patch :unpublish,     on: :member

      # 手動スロット編集（単発API）
      patch :update_slot,   on: :member

      # 差し替え候補取得
      get :available_members, on: :member

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
      patch :reorder,        on: :collection
      patch :swap,           on: :collection
      patch :clear_slot,     on: :member
      patch :replace_member, on: :member

      # まとめて更新（StimulusがPOSTで送るためPOSTも受ける）
      patch :bulk_update, on: :collection
      post  :bulk_update, on: :collection
    end
  end

  # 公開側
  resources :events, only: [:index, :show]

  # サービス内容ページ
  get "/service", to: "pages#service", as: :service

  # ルート
  root "events#index"
end