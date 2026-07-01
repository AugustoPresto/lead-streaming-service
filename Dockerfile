# syntax=docker/dockerfile:1

# 1. Frontend builder stage
FROM node:20-slim AS frontend-builder
WORKDIR /frontend
COPY frontend/package.json frontend/package-lock.json ./
RUN npm ci
COPY frontend/ ./
RUN npm run build

# 2. Base stage
FROM ruby:3.2.2-slim AS base

WORKDIR /app

# Install runtime dependencies
RUN apt-get update -qq && \
    apt-get install --no-install-recommends -y \
    postgresql-client \
    curl \
    git \
    build-essential \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 3. Builder stage: Install gems
FROM base AS builder

COPY Gemfile Gemfile.lock ./

# Install and build native gems
RUN bundle config set --local without 'development test' && \
    bundle install --jobs 4 --retry 3

# 4. Final production stage
FROM base AS runner

# Copy installed gems and application code
COPY --from=builder /usr/local/bundle /usr/local/bundle
COPY . .

# Copy built React frontend assets to Rails public folder
COPY --from=frontend-builder /frontend/dist /app/public

# Set production env
ENV RAILS_ENV=production
ENV RAILS_LOG_TO_STDOUT=true
ENV RAILS_SERVE_STATIC_FILES=true

EXPOSE 3000

# Start script
CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]
