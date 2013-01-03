require 'rubygems'
require 'bundler/setup'

require 'yaml'
require './imap_classifier'

if ARGV.length < 2
puts <<EOH
Usage: manualclassify.rb email_address symbol [account]

Manually learn that email_address should be put in folder specified by symbol.
Specify an account config name (from config/imap.yml) for accountgroup or
'default' will be used.

Symbol can be:
 b    - email_address should go to black hole
 i    - mail from email_address should stay in inbox
 l    - mail from email_address should be moved to @Later

Example: manualclassify.rb spam@spammer.com b gmail
         -> Send all mail from spam@spammer.com coming to any
         mailbox that has the same accountgroup as 'gmail' to
         blackhole (=immediate delete)
EOH
else
email = ARGV[0]
classification = ARGV[1]
configuration = ARGV[2] || 'default'

imap_config = YAML.load_file('config/imap.yml')[configuration]
imap_classifier = ImapClassifier.new(imap_config)

imap_classifier.manual_classify(email, classification)
end
