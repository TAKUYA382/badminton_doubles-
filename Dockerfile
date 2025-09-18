# syntax = docker/dockerfile:1

# 本番用のDockerfile（開発用ではありません）
# 例:
# docker build -t my-app .
# docker run -d -p 80:80 -p 443:443 --name my-app -e RAILS_MASTER_KEY=<value from config/master.key> my-app

# .ruby-version と合わせる
ARG RUBY_VERSION=3.4.5
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base

# Rails app の作業ディレクトリ
WORKDIR /rails

# --- 実行時に必要なパッケージ（PostgreSQL用ランタイムライブラリを追加）---
# libpq5: pg(gem) の実行に必要
# libvips: ActiveStorageの画像処理系（必要な場合）
# libjemalloc2: メモリ効率（任意）
# sqlite3: ローカル/一部ツールで使うなら残してOK（不要なら消しても可）
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      curl \
      libjemalloc2 \
      libvips \
      sqlite3 \
      libpq5 \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# 本番環境変数
ENV RAILS_ENV="production" \
    BUNDLE_DEPLOYMENT="1" \
    BUNDLE_PATH="/usr/local/bundle" \
    BUNDLE_WITHOUT="development:test"

# ------------------ ここからビルド用ステージ ------------------
FROM base AS build

# pg のコンパイルに必要なヘッダ等（libpq-dev）と YAML（libyaml-dev）
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
      build-essential \
      git \
      pkg-config \
      libpq-dev \
      libyaml-dev \
    && rm -rf /var/lib/apt/lists /var/cache/apt/archives

# Gem をインストール
COPY Gemfile Gemfile.lock ./
RUN bundle install && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache "${BUNDLE_PATH}"/ruby/*/bundler/gems/*/.git && \
    bundle exec bootsnap precompile --gemfile

# アプリケーションコードをコピー
COPY . .

# bootsnap のプリコンパイル
RUN bundle exec bootsnap precompile app/ lib/

# bin の改行/実行権限調整（Windows→Linux対策）
RUN chmod +x bin/* && \
    sed -i "s/\r$//g" bin/* && \
    sed -i 's/ruby\.exe$/ruby/' bin/*

# アセットプリコンパイル（RAILS_MASTER_KEY なしで実行）
RUN SECRET_KEY_BASE_DUMMY=1 ./bin/rails assets:precompile

# ------------------ 本番実行用ステージ ------------------
FROM base

# build ステージから成果物をコピー（Gem とアプリ）
COPY --from=build "${BUNDLE_PATH}" "${BUNDLE_PATH}"
COPY --from=build /rails /rails

# 権限設定（非rootで実行）
RUN groupadd --system --gid 1000 rails && \
    useradd rails --uid 1000 --gid 1000 --create-home --shell /bin/bash && \
    chown -R rails:rails db log storage tmp
USER 1000:1000

# DB準備などのエントリポイント
ENTRYPOINT ["/rails/bin/docker-entrypoint"]

# デフォルトはRailsサーバ起動
EXPOSE 3000
CMD ["./bin/rails", "server"]
