source 'http://rubygems.org'

platform :jruby do
  gem 'mondrian-olap', :git => 'https://github.com/rsim/mondrian-olap.git'
  gem 'null_logger'
  gem 'grape'

  group :development do
    gem 'ruby-debug'
    gem 'rake'
    gem 'pry'
  end

  group :test do
    gem 'rspec'
    gem 'jdbc-derby'
    gem 'jdbc-sqlite3'
    gem 'rack-test'
    gem 'rubyzip'
  end
end
