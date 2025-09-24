# syntax = docker/dockerfile:1

ARG RUBY_VERSION=3.3.5
FROM docker.io/library/ruby:${RUBY_VERSION}-slim AS base

WORKDIR /app

RUN apt-get update -qq && apt-get install --no-install-recommends -y \
  curl \
  libpq5 \
  libvips \
  libjemalloc2 \
  && rm -rf /var/lib/apt/lists/*

ENV RAILS_ENV=production \
    RACK_ENV=production \
    BUNDLE_WITHOUT="development:test" \
    PORT=3000

FROM base AS build

RUN apt-get update -qq && apt-get install --no-install-recommends -y \
  build-essential \
  git \
  pkg-config \
  libpq-dev \
  libyaml-dev \
  nodejs \
  && rm -rf /var/lib/apt/lists/*

COPY Gemfile Gemfile.lock ./
RUN bundle install --jobs 4 --retry 3 && \
    rm -rf ~/.bundle/ "${BUNDLE_PATH}"/ruby/*/cache

COPY . .

RUN SECRET_KEY_BASE=dummy bundle exec rails assets:precompile

FROM base

COPY --from=build /usr/local/bundle /usr/local/bundle
COPY --from=build /app /app

RUN groupadd --system rails && \
    useradd rails --system --gid rails --create-home && \
    chown -R rails:rails /app
USER rails

EXPOSE 3000

CMD bash -lc "bundle exec rails db:migrate && bundle exec puma -C config/puma.rb"
