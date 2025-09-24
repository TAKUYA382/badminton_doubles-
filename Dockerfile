# syntax = docker/dockerfile:1

# 本番用のDockerfile（Renderデプロイ用）
# 例:
# docker build -t my-app .
# docker run -d -p 3000:3000 --name my-app -e RAILS_MASTER_KEY=<config/master.keyの値> my-app

# RubyバージョンをGemfileと合わせる
ARG RUBY_VERSION=3.4.0
FROM ruby:$RUBY_VERSION-slim AS base

# Railsアプリの作業ディレクトリ
WORKDIR /app

# -------------------------
# 1. 実行時に必要なパッケージ
# -------------------------
# - libpq5: PostgreSQLランタイム
# - libvips: ActiveStorageで画像処理を使う場合
# - libjemalloc2: メモリ効率化（任意）
RUN apt-get update -qq && apt-get install --no-install-recommends -y \
  curl \
  libpq5 \
  libvips \
  libjemalloc2 \
  && rm -rf /var/lib/apt/lists/*

# 環境変数
ENV RAILS_ENV=production \
    RACK_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    PORT=3000

# -------------------------
# 2. ビルド用パッケージ（pgビルドやYAML用）
# -------------------------
FROM base AS build

RUN apt-get update -qq && apt-get install --no-install-recommends -y \
  build-essential \
  git \
  pkg-config \
  libpq-dev \
  libyaml-dev \
  nodejs \
  && rm -rf /var/lib/apt/lists/*

# Gemfile関連のみ先にコピーしてbundle install
COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3 && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache

# 残りのアプリケーションコードをコピー
COPY . .

# アセットのプリコンパイル（SECRET_KEY_BASEは仮でOK）
RUN SECRET_KEY_BASE=dummy bundle exec rails assets:precompile

# -------------------------
# 3. 本番用ステージ
# -------------------------
FROM base

# buildステージからGemとアプリをコピー
COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

# 権限設定（非rootユーザーで実行）
RUN groupadd --system rails && \
    useradd rails --system --gid rails --create-home && \
    chown -R rails:rails /app
USER rails

# ポート公開
EXPOSE 3000

# 起動時にDBマイグレーション後、Pumaを起動
CMD bash -lc "bundle exec rails db:migrate && bundle exec puma -C config/puma.rb"
