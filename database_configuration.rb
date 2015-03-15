require 'rubygems'
require 'active_record'
require 'logger'

DATABASE_ENV = ENV['DATABASE_ENV'] || 'development'
ActiveRecord::Base.establish_connection(YAML.load_file('config/databases.yml')[DATABASE_ENV])


ActiveRecord::Base.logger = Logger.new(STDERR)


