source "https://rubygems.org"

ruby "3.2.2"

gem "rails", "~> 7.1.5"
gem "pg", "~> 1.1"
gem "puma", ">= 5.0"
gem "bootsnap", require: false

# Data Streaming & Event Validation
gem "dry-validation", "~> 1.10"

# Analytics Databases (Pure-Ruby Client Libraries for lightweight installation)
gem "clickhouse-ruby", "~> 0.3.0"
gem "elasticsearch", "~> 8.12"

# Observability
gem "sentry-ruby", "~> 5.17"
gem "sentry-rails", "~> 5.17"
gem "yabeda-prometheus", "~> 0.9.0"
gem "yabeda-rails", "~> 0.9.0"

group :development, :test do
  gem "debug", platforms: %i[ mri windows ]
  gem "rspec-rails", "~> 6.1"
  gem "factory_bot_rails", "~> 6.4"
  gem "faker", "~> 3.2"
end

group :test do
  gem "webmock", "~> 3.23"
end

