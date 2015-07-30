require 'rubygems'
require 'bundler/setup'

require 'yaml'
require './imap_classifier'
require 'highline'

def help
	puts <<eos
Usage: imap-readlater.rb [-c] [-f] [-D] [-r] [-v] [-d] [configurations...]

Process and classify all configurations (specified in config/imap.yml) specified
on command line or configuration called 'default' if none are specified

	-h	Help
	-c	Do classification
	-f	Fetch and learn (this needs to be run at least once)
	-D	Daemon mode. Daemon processes all accounts and does fetch and
		learn and classification by default. If -c or -f is specified,
		only classification or learning will be performed
	-a	Process all messages, not only recent
	-v	Verbose
	-d	Dry run (do not move any messages, just write what would be
		done)


eos
end

def classify(imap_classifier, move_messages, filter, verbose)

	imap_classifier.classify_folder('INBOX', filter, move_messages)

	# handle all learning forced by user (manual learn) - dragging around folders
	imap_classifier.manual_learn_all(move_messages, filter)
end

def fetch_headers(imap_classifier, filter, verbose)
	imap_classifier.folders.each do |folder|
		puts "Processing folder #{folder} using filter #{filter}" if verbose
		imap_classifier.learn_from_folder(folder, filter)
	end
end

run_each = 100 # In daemon mode, process all accounts every run_each seconds
fetch_every = 10 # In daemon mode, do learning on all folders every fetch_every runs

do_classify = ARGV.delete("-c")
do_fetchheaders = ARGV.delete("-f")
daemon = ARGV.delete("-D")
process_all = ARGV.delete("-a")
verbose = ARGV.delete("-v")
dry_run = ARGV.delete("-d")

if daemon and not (do_classify or do_fetchheaders)
	do_classify=true
	do_fetchheaders=true
end

move_messages=true
if dry_run 
   move_messages=false
end

accounts = ARGV

if accounts.size > 0
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

puts "Starting #{daemon ? 'daemon mode ' : ''}for accounts: #{accounts.join(', ')}" if verbose

classifiers = [ ]
config_file = YAML.load_file('config/imap.yml')
accounts.each do |account_desc|

	imap_config = config_file[account_desc]
	if imap_config['password'].casecmp("ask") == 0
		imap_config['password'] = HighLine.new.ask("Password for #{imap_config['login']}@#{imap_config['imapserver']} from configuration #{account_desc}:  ") { |q| q.echo = false }
	end
	imap_classifier = ImapClassifier.new(imap_config)

	imap_classifier.connect

#  if verbose
#		puts "I can see these folders for #{imap_config['login']}@#{imap_config['imapserver']}:"
#		imap_classifier.list_folders.each do |f|
#		  puts "#{f}"
#    end
#  end

	classifiers << imap_classifier

end

run = 0
first_run = true

filter="ALL"

unless process_all
	filter="OR RECENT SINCE #{Net::IMAP.format_date(Date.today.weeks_ago(1))}"
end

while daemon or first_run
  errors_in_run = 0
	classifiers.each do |imap_classifier|
		begin
      imap_classifier.connect unless imap_classifier.connected?
			if do_fetchheaders and (run.modulo(fetch_every) == 0)
				puts "Fetching headers for #{imap_classifier.imap_config['login']}@#{imap_classifier.imap_config['imapserver']}" if verbose
				fetch_headers(imap_classifier, filter , verbose)
				run = 0
			end	

			if do_classify
				puts "Doing classification for #{imap_classifier.imap_config['login']}@#{imap_classifier.imap_config['imapserver']}" if verbose
				classify(imap_classifier, move_messages, filter, verbose)
			end
		
		rescue Errno::EPIPE, Net::IMAP::ByeResponseError, EOFError, IOError, Errno::ETIMEDOUT, Net::IMAP::NoResponseError, Errno::ECONNREFUSED, Errno::ECONNRESET, Net::IMAP::ResponseParseError, Errno::EHOSTUNREACH => e
			errors_in_run += 1
			puts STDERR, "Connection error: Connection closed unexpectedly (#{imap_classifier.imap_config['login']}@#{imap_classifier.imap_config['imapserver']}"
			puts STDERR, e.message
			if daemon
				puts STDERR, "Daemon mode, reconnecting and continuing."
				begin
								imap_classifier.connect
		    rescue Errno::EPIPE, Net::IMAP::ByeResponseError, EOFError, IOError, Errno::ETIMEDOUT, Net::IMAP::NoResponseError, Errno::ECONNREFUSED, Errno::ECONNRESET, Net::IMAP::ResponseParseError, Errno::EHOSTUNREACH => e
								puts STDERR, "Unable to connect, will retry on next run."
				end
			end
		end
	end
	filter="OR RECENT SINCE #{Net::IMAP.format_date(Date.yesterday)}" if first_run
  unless errors_in_run
	  run += 1
	  first_run = false
  end

	sleep run_each if daemon
end
