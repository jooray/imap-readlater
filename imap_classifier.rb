require 'net/imap'
require './schema'
require 'yaml'

class ImapClassifier

DEBUG=true

def initialize(configuration)
	@imap_config = YAML.load_file('config/imap.yml')['default']
end

def connect
	@imap = Net::IMAP.new(@imap_config['imapserver'], @imap_config['imapport'], @imap_config['ssl'])
	@imap.login(@imap_config['login'], @imap_config['password'])
end

def learn_message(uid, envelope)
  if known_uid?(uid)
	dd "UID #{uid} already known"
	return
  end
  c=Conversation.new
  unless envelope.from.nil? or envelope.from[0].nil?
	  c.frommailbox = envelope.from[0].mailbox
	  c.fromdomain = envelope.from[0].host
  end
  unless envelope.to.nil? or envelope.to[0].nil?
          c.tomailbox = envelope.to[0].mailbox
          c.todomain = envelope.to[0].host
  end
  c.conversations = 0


  conversations = Conversation.where("frommailbox = ? AND fromdomain = ? AND tomailbox = ? AND todomain = ?", c.frommailbox, c.fromdomain, c.tomailbox, c.todomain)

  unless conversations.nil? or conversations[0].nil?
    c=conversations[0]
  end

  dd "#{uid} #{c.frommailbox}@#{c.fromdomain} -> #{c.tomailbox}@#{c.todomain}: \t#{c.conversations}"

  mark_as_seen(uid)

  c.conversations+=1
  begin
    c.save
  rescue ActiveRecord::StatementInvalid => e
    dd e
  end



end


def message_classification(uid, envelope)
	mailbox=envelope.from[0].mailbox
	domain=envelope.from[0].host
	# if we already know classification, print that

	c = Classification.find_by_mailbox_and_domain(mailbox, domain)
	unless c.nil?
		#dd "Mail from #{mailbox}@#{domain} already classified as #{c.movetolater? ? "read later" : "stay in inbox"} by #{c.byuser? ? "user" : "machine"}"
		return c.movetolater?
	end

	# if we reply to the sender of this message (often), keep it in inbox
	# TODO: often could be also percentage if there's a large number of e-mails

	conversations=Conversation.find_all_by_tomailbox_and_todomain(mailbox, domain).select {|a| is_myaddr("#{a.frommailbox}@#{a.fromdomain}") }
	count = 0
	unless conversations.nil?
		conversations.each do |r|
			unless r.nil?
				count+=1
			end
		end
	end
	read_later=false
	save_classification = true
	if count < 1
		# OK, our user does not write to this address. Is this address new?
		a=Conversation.find_by_frommailbox_and_fromdomain(mailbox, domain)
		if a.nil? or a.conversations < 1
			# this address is new. Keep in inbox, but don't remember classification =>
			# if the user does not reply to this e-mail, new e-mail from this address
			# goes to read later next time
			save_classification = false
		else
			read_later = true
		end
	end

	if save_classification
		cl = Classification.new
		cl.mailbox = mailbox
		cl.domain = domain
		cl.byuser = false
		cl.movetolater = read_later
		cl.save
	end

	learn_message(uid, envelope) # record the conversation

	dd "Mail from #{mailbox}@#{domain} classified as #{read_later ? "read later" : "stay in inbox"}"
	read_later

end

def learn_from_folder(folder, filter="ALL")
	foreach_msg_in_folder(folder, filter) { |uid, envelope| learn_message(uid, envelope) }
end

def classify_folder(folder, filter="ALL", move_messages=false)
	if move_messages 
		create_folder_if_nonexistant(@imap_config['laterfolder'])
	end
	errorless = true
	foreach_msg_in_folder(folder, filter, (not move_messages)) do |uid, envelope|
		unless known_uid?(uid)
			if message_classification(uid, envelope) and move_messages
				begin
				  dd "Moving #{uid} to read_later"
				  @imap.uid_copy(uid, @imap_config['laterfolder'])
				  @imap.uid_store(uid, "+FLAGS", [:Deleted])
				rescue Exception => e
				  de "Error occured while moving message #{uid}: #{e.message}"
				  de e.backtrace.inspect
				  errorless = false
				end
			end
		end
	end
	if errorless
		@imap.expunge
	end
	errorless
end

def print_uuid(uid, envelope)
	dd "#{envelope.from[0].mailbox}@#{envelope.from[0].host}: #{uid}"
end

def print_uids_in_folder(folder, filter="ALL")
	foreach_msg_in_folder(folder, filter) { |uid, envelope| print_uuid uid,envelope }
end

private

def foreach_msg_in_folder(folder, filter="ALL", read_only=true)
	if read_only
		@imap.examine(folder)
	else
		@imap.select(folder)
	end
	@imap.search(filter).each do |msg_id|
	  msg = @imap.fetch(msg_id, ["UID", "ENVELOPE"])[0]
	  envelope = msg.attr["ENVELOPE"]
	  uid = msg.attr["UID"]
 
          yield uid, envelope

	end

end


def dd(what)
	puts "#{what}" if DEBUG
end

def de(what)
	puts "#{what}"
end

def known_uid?(uid)
	not SeenUid.find_by_uid(uid).nil?
end

def mark_as_seen(uid)
	seen = SeenUid.new
	seen.uid = uid
	seen.save
end

# all addresses are mine if myfromaddr not defined
def is_myaddr(addr)
	if @imap_config['myfromaddr'].nil?
		return true
	end
	@imap_config['myfromaddr'].each do |a|
		if a == addr
			 return true
		end
		reg=Regexp.new(a)
		unless reg.match(addr).nil?
			 return true
		end
	end
	false
end

def create_folder_if_nonexistant(folder)
	unless @imap.list("", folder) 
		imap.create(folder)
	end
end


end
