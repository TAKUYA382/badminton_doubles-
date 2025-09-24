source "https://rubygems.org"

ruby ">= 3.3.0", "< 3.5"

gem "rails", "~> 7.2.2", ">= 7.2.2.2"
gem "puma", ">= 5.0"
gem "sprockets-rails"
gem "importmap-rails"
gem "turbo-rails"
gem "stimulus-rails"
gem "jbuilder"
gem "bootsnap", require: false
gem "tzinfo-data"    
gem "devise", "~> 4.9"
gem "nokogiri", "~> 1.18"

group :development, :test do
  gem "sqlite3", "~> 1.7"           
  gem "dotenv-rails"                
  gem "debug", platforms: %i[mri windows], require: "debug/prelude"
  gem "brakeman", require: false
  gem "rubocop-rails-omakase", require: false
end

group :development do
  gem "web-console"
end

group :test do
  gem "capybara"
  gem "selenium-webdriver"
end

group :production do
  gem "pg"
end
