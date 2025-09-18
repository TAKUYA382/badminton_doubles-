source "https://rubygems.org"

# （任意）使っている Ruby を明記
# ruby "3.4.0"

gem "rails", "~> 7.2.2", ">= 7.2.2.2"
gem "sprockets-rails"
gem "puma", ">= 5.0"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"

# Windows は zoneinfo がないので必須
gem "tzinfo-data"

# 起動高速化
gem "bootsnap", require: false

# Devise
gem "devise", "~> 4.9"

# Nokogiri
gem "nokogiri", "~> 1.18"

# ==== ここから環境別 ====

# 開発・テスト（ローカル）は SQLite / .env を読み込む
group :development, :test do
  # SQLite は 1.7 系を推奨（Windows でも安定）
  gem "sqlite3", "~> 1.7"
  gem "dotenv-rails"         # .env を読み込む
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

# 開発専用
group :development do
  gem "web-console"
end

# テスト専用
group :test do
  gem "capybara"
  gem "selenium-webdriver"
end

# 本番（Render）は PostgreSQL
group :production do
  gem "pg"
end
