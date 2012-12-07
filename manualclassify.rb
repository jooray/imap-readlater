require 'yaml'
require './imap_classifier'

if ARGV.length < 2
puts "Usage: manualclassify.rb email_address symbol"
puts "Symbol can be:"
puts " b    - email_address should go to black hole"
puts " i    - mail from email_address should stay in inbox"
puts " l    - mail from email_address should be moved to @Later"
else
email = ARGV[0]
classification = ARGV[1]

imap_config = YAML.load_file('config/imap.yml')['default']
imap_classifier = ImapClassifier.new(imap_config)

imap_classifier.manual_classify(email, classification)
end
