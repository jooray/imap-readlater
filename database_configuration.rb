require 'rubygems'
require 'active_record'

DATABASE_ENV = ENV['DATABASE_ENV'] || 'development'
ActiveRecord::Base.establish_connection(YAML.load_file('config/databases.yml')[DATABASE_ENV])

