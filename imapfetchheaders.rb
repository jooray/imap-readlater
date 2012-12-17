require 'yaml'
require './imap_classifier'
gem 'activesupport'
require 'active_support/core_ext/date/calculations.rb'
require 'net/imap'

recent = ARGV.delete("-r")

account_desc = ARGV[0] || "default"

imap_config = YAML.load_file('config/imap.yml')[account_desc]
imap_classifier = ImapClassifier.new(imap_config)

imap_classifier.connect

folders = imap_config['folders']

filter="ALL"

if recent
	filter="OR RECENT SINCE #{Net::IMAP.format_date(Date.yesterday)}"
end

folders.each do |folder|
	puts "Processing folder #{folder} using filter #{filter}"
	imap_classifier.learn_from_folder(folder, filter)
end


