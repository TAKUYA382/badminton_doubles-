# config/application.rb
require_relative "boot"

require "rails/all"
require "tzinfo/data"

# Gemfile の gem を読み込む
Bundler.require(*Rails.groups)

module Takuya2
  class Application < Rails::Application
    # 既定値は使っている Rails に合わせる
    config.load_defaults 7.2

    # ===== タイムゾーン / ロケール =====
    config.time_zone = "Tokyo"
    config.active_record.default_timezone = :local

    config.i18n.default_locale = :ja
    config.i18n.available_locales = %i[ja en]
    # /config/locales 以下の yml/rb をすべて読み込み
    config.i18n.load_path += Dir[Rails.root.join("config/locales/**/*.{rb,yml}").to_s]
    # 翻訳が無いキーは英語にフォールバック（あれば）
    config.i18n.fallbacks = [:en]

    # ===== autoload / eager load =====
    # lib 以下を自動読み込み対象に
    config.autoload_lib(ignore: %w[assets tasks])
    config.autoload_paths << Rails.root.join("lib")

    # 本番での eager load 対象を追加（必要に応じて）
    config.eager_load_paths << Rails.root.join("lib")
    config.eager_load_paths << Rails.root.join("app/services")
    config.eager_load_paths << Rails.root.join("app/validators")

    # ===== ジェネレータ（お好み）=====
    # 余計なファイルを作らないよう調整
    config.generators do |g|
      g.assets false
      g.helper false
      g.stylesheets false
      g.jbuilder false
      g.test_framework :rspec, fixture: false
    end

    # ===== View / フォームの細かい調整（任意）=====
    # form_with の既定は Turbo/remote だが、各フォームで local: true を明示しているので変更不要
    # フォームエラー時に <div class="field_with_errors"> を付与しない
    config.action_view.field_error_proc = ->(html_tag, _instance) { html_tag.html_safe }
  end
end