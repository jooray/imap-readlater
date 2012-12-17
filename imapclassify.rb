require 'yaml'
require './imap_classifier'

def classify(imap_classifier)
	imap_classifier.classify_folder('INBOX', "ALL", move_messages)

	# handle all learning forced by user (manual learn) - dragging around folders
	imap_classifier.manual_learn_all(move_messages)
end

def fetch_headers(imap_classifier, imap_config)
	folders = imap_config['folders']

	filter="ALL"

	if recent
		filter="OR RECENT SINCE #{Net::IMAP.format_date(Date.yesterday)}"
	end

	folders.each do |folder|
		puts "Processing folder #{folder} using filter #{filter}"
		imap_classifier.learn_from_folder(folder, filter)
	end
end

classify = ARGV.delete("-c")
fetchheaders = ARGV.delete("-f")
daemon = ARGV.delete("-D")
recent = ARGV.delete("-r")

if daemon and not (classify and fetchheaders)
	classify=true
	fetchheaders=true
end

dry_run = ARGV.delete("-d")
move_messages=true
if dry_run 
   move_messages=false
end

accounts = ARGV

if ARGV.size > 0
	ARGV.each do |a|
		if a[0]=='-'
			puts "Unknown parameter: #{a}"
			help
			exit(2)
		end
	end
	accounts = ARGV
	
else
	accounts = [ 'default' ]
end

imap_config = YAML.load_file('config/imap.yml')[account_desc]
imap_classifier = ImapClassifier.new(imap_config)

imap_classifier.connect


