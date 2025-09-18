# config/application.rb
require_relative "boot"

require "rails/all"
require "tzinfo/data"

# Gemfile の gem を読み込む
Bundler.require(*Rails.groups)

module Takuya2
  class Application < Rails::Application
    config.load_defaults 7.2

    # 日本時間設定
    config.time_zone = "Tokyo"
    config.active_record.default_timezone = :local
    config.autoload_lib(ignore: %w[assets tasks])
    config.i18n.default_locale = :ja
    config.i18n.available_locales = %i[ja en]
    config.i18n.load_path += Dir[Rails.root.join('config/locales/**/*.{rb,yml}').to_s]
  end
end
