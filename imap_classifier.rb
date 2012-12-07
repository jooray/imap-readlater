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

def message_check_manual_learn(uid, envelope, symbol = 'i')
	mailbox=envelope.from[0].mailbox
	domain=envelope.from[0].host

	# is this a known message moved from other folder ?
	msgid = MessageId.find_by_message_id(envelope.message_id)
	if msgid.nil?   # we have not seen this message, let's just save it
		msgid=MessageId.new
		msgid.message_id=envelope.message_id
		msgid.last_seen=symbol
		msgid.save
		false
	elsif msgid.last_seen != symbol
		handle_manual_learn(uid, envelope, msgid.last_seen, symbol)
		true
	else
		false
	end
end


def message_classification(uid, envelope)
	mailbox=envelope.from[0].mailbox
	domain=envelope.from[0].host

	# if we already know classification, print that
	c = Classification.find_by_mailbox_and_domain(mailbox, domain)
	unless c.nil?
		#dd "Mail from #{mailbox}@#{domain} already classified as #{c.movetolater? ? "read later" : "stay in inbox"} by #{c.byuser? ? "user" : "machine"}"
		return classification_to_symbol(c.movetolater, c.blackhole)
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
	blackhole=false
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

	symbol = classification_to_symbol(read_later, blackhole)
	register_message(uid, envelope, symbol) # register the message-id for detecting manual learning

	dd "Mail from #{mailbox}@#{domain} classified as #{read_later ? "read later" : "stay in inbox"}"
	symbol

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
		# unless someone moved this message from other folder back to inbox (=> learn)
		# or unless we have already processed it, perform classification
		unless message_check_manual_learn(uid, envelope, 'i') or known_uid?(uid)
			symbol = message_classification(uid, envelope)
			if symbol != 'i' and move_messages
				begin
				  if symbol == 'l'
				  	  dd "Moving #{uid} to read_later"
					  @imap.uid_copy(uid, @imap_config['laterfolder'])
					  @imap.uid_store(uid, "+FLAGS", [:Deleted])
				  elsif symbol == 'b'
				  	  dd "Deleting: #{uid} blackholed"
					  @imap.uid_store(uid, "+FLAGS", [:Deleted])
				  end
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

def handle_manual_learn(uid, envelope, oldsymbol, newsymbol)
        mailbox=envelope.from[0].mailbox
        domain=envelope.from[0].host

	c = Classification.find_by_mailbox_and_domain(mailbox, domain)
	if c.nil?
		c=Classification.new
		c.mailbox=mailbox
		c.domain=domain
	end

	c.byuser=true

	c.movetolater = (newsymbol == 'l')
	c.blackhole = (newsymbol == 'b')

	c.save

	message_id = MessageId.find_by_message_id(envelope.message_id)
	if message_id
		message_id.last_seen=newsymbol
		message_id.save
	end
	dd "Manually learned that #{mailbox}@#{domain} should #{c.movetolater ? "" : "not"} move to Later and should #{c.blackhole ? "" : "not"} be in blackhole" 
end

def train_from_folder(folder, symbol, filter="ALL")
	foreach_msg_in_folder(folder, filter) do |uid, envelope|
		oldsymbol=register_message(uid, envelope, symbol)
		if oldsymbol != symbol
			handle_manual_learn(uid, envelope, oldsymbol, symbol)
		end
	end
end

def folder_check_manual_learn(folder, symbol, filter = 'ALL', delete_after_classification = false)
	@imap.select(folder)
	@imap.expunge
	foreach_msg_in_folder(folder, filter, (not delete_after_classification)) do |uid, envelope|
		message_check_manual_learn(uid, envelope, symbol)
		if delete_after_classification
			 @imap.uid_store(uid, "+FLAGS", [:Deleted])
		end
	end
	@imap.expunge if delete_after_classification
end

def manual_learn_all(move_messages = true)
	create_folder_if_nonexistant(@imap_config['laterfolder'])
	create_folder_if_nonexistant(@imap_config['blackholefolder'])
	folder_check_manual_learn(@imap_config['laterfolder'], 'l', 'ALL', false)
	folder_check_manual_learn(@imap_config['blackholefolder'], 'b', 'ALL', move_messages)
end


def manual_classify(email, symbol)
	mailbox, domain = email.split(/@/)
	c = Classification.find_by_mailbox_and_domain(mailbox, domain)
	unless c
		c=Classification.new
		c.mailbox=mailbox
		c.domain=domain
	end
	c.byuser=true
	c.movetolater=symbol_to_movetolater(symbol)
	c.blackhole=symbol_to_blackhole(symbol)
	c.save
end

private

def symbol_to_movetolater(symbol)
	symbol == 'l'
end

def symbol_to_blackhole(symbol)
	symbol == 'b'
end
def classification_to_symbol(movetolater, blackhole)
		symbol = 'i'
		if blackhole
			symbol = 'b'
		elsif movetolater
			symbol = 'l'
		end
		symbol
end

def register_message(uid, envelope, symbol)
		message_id = envelope.message_id
		m=MessageId.find_by_message_id(message_id)
		if m
			if m.last_seen != symbol
				oldsymbol=symbol
				m.last_seen = symbol
				m.save
				return oldsymbol
			end
		else
			m=MessageId.new
			m.message_id=message_id
			m.last_seen=symbol
		end
		symbol
end

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
		@imap.create(folder)
	end
end


end
