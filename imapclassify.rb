require 'yaml'
require './imap_classifier'

dry_run = ARGV.delete("-d")
move_messages=true
if dry_run 
   move_messages=false
end

imap_config = YAML.load_file('config/imap.yml')['default']
imap_classifier = ImapClassifier.new(imap_config)

imap_classifier.connect

imap_classifier.classify_folder('INBOX', "ALL", move_messages)

