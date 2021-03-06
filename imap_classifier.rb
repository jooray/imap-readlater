require 'net/imap'
require './schema'
require 'yaml'

class ImapClassifier

DEBUG=true

def initialize(configuration)
	@imap_config = configuration
  @connected = false
	@filter = "ALL"
end

def connect

  @connected=false

	@imap = Net::IMAP.new(@imap_config['imapserver'], @imap_config['imapport'], @imap_config['ssl'])
	@imap.login(@imap_config['login'], @imap_config['password'])

	unless @imap_config['accountgroup']
		@imap_config['accountgroup']="#{@imap_config['login']}@#{@imap_config['imapserver']}"
	end

	unless ImapAccount.find_by_imap_group(@imap_config['accountgroup'])
		dd "This account group is seen for the first time, copying default domain rules for bulk mail classification"
		copy_template_rules
	end

	account = ImapAccount.find_by_login_and_server(@imap_config['login'], @imap_config['imapserver'])
	if account.nil?
		account=ImapAccount.new
		account.login=@imap_config['login']
		account.server=@imap_config['imapserver']
		account.imap_group=@imap_config['accountgroup']
		account.save
	elsif account.imap_group != @imap_config['accountgroup']
		account.imap_group=@imap_config['accountgroup']
		account.save
	end

	@account=account
	
  @connected=true
end

def connected?
  @connected
end

def folders
	@imap_config['folders']
end

def imap_config
	@imap_config
end

def learn_message(uid, envelope)
  if known_uid?(uid)
	#dd "UID #{uid} already known"
	  return
  end
	if envelope.nil?
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
  c.imap_group=@account.imap_group


  conversations = Conversation.where("frommailbox = ? AND fromdomain = ? AND tomailbox = ? AND todomain = ? AND imap_group = ?", c.frommailbox, c.fromdomain, c.tomailbox, c.todomain, @account.imap_group)

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
	msgid = find_message_id(envelope.message_id)
	if msgid.nil?   # we have not seen this message, let's just save it
		msgid=MessageId.new
		msgid.message_id=envelope.message_id
		msgid.last_seen=symbol
		msgid.imap_account=@account
		msgid.save
		false
	elsif msgid.last_seen != symbol
		handle_manual_learn(uid, envelope, msgid.last_seen, symbol)
		true
	else
		true
	end
end


def message_classification(uid, envelope)
	mailbox=envelope.from[0].mailbox
	domain=envelope.from[0].host

	# if we already know classification, print that
	c = Classification.find_by_mailbox_and_domain_and_imap_group(mailbox, domain, @account.imap_group)
	c = Classification.find_by_mailbox_and_domain_and_imap_group('%', domain, @account.imap_group) if c.nil?
	unless c.nil?
		#dd "Mail from #{mailbox}@#{domain} already classified as #{c.movetolater? ? "read later" : "stay in inbox"} by #{c.byuser? ? "user" : "machine"}"
		symbol = classification_to_symbol(c.movetolater, c.blackhole)
		register_message(uid, envelope, symbol) # register the message-id for detecting manual learning
		return symbol
	end

	# if we reply to the sender of this message (often), keep it in inbox
	# TODO: often could be also percentage if there's a large number of e-mails

	conversations=Conversation.find_all_by_tomailbox_and_todomain_and_imap_group(mailbox, domain, @account.imap_group).select {|a| is_myaddr("#{a.frommailbox}@#{a.fromdomain}") }
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
		a=Conversation.find_by_frommailbox_and_fromdomain_and_imap_group(mailbox, domain, @account.imap_group)
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
		cl.imap_group = @account.imap_group
		cl.save
	end

	learn_message(uid, envelope) # record the conversation

	symbol = classification_to_symbol(read_later, blackhole)
	register_message(uid, envelope, symbol) # register the message-id for detecting manual learning

	dd "Mail from #{mailbox}@#{domain} classified as #{read_later ? "read later" : "stay in inbox"}"
	symbol

end

def learn_from_folder(folder)
	foreach_msg_in_folder(folder, @filter) { |uid, envelope| learn_message(uid, envelope) }
end

def classify_folder(folder, move_messages=false)
	if move_messages 
		create_folder_if_nonexistant(@imap_config['laterfolder'])
	end
	errorless = true
	foreach_msg_in_folder(folder, @filter, (not move_messages)) do |uid, envelope|
		# unless someone moved this message from other folder back to inbox (=> learn)
		# or unless we have already processed it, perform classification
		unless message_check_manual_learn(uid, envelope, 'i')
			symbol = message_classification(uid, envelope)
			if symbol != 'i' and move_messages
				begin
				  if symbol == 'l'
				  	  dd "Moving #{envelope.from[0].mailbox}@#{envelope.from[0].host} to read_later"
					  @imap.uid_copy(uid, @imap_config['laterfolder'])
					  @imap.uid_store(uid, "+FLAGS", [:Deleted])
				  elsif symbol == 'b'
				  	  dd "Deleting: #{envelope.from[0].mailbox}@#{envelope.from[0].host} blackholed"
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
	if errorless and move_messages
		@imap.expunge
	end
	errorless
end

def handle_manual_learn(uid, envelope, oldsymbol, newsymbol)
        mailbox=envelope.from[0].mailbox
        domain=envelope.from[0].host

	c = Classification.find_by_mailbox_and_domain_and_imap_group(mailbox, domain, @account.imap_group)

	# What should be the behaviour? If we have a full-domain rule and user reclassifies, should we
	# reclassify whole domain or just the particular sender?
	# We'll leave it as domain unless it's a blackhole (it's a safer thing to do than to blackhole a whole
	# domain)
	if c.nil? and newsymbol!='b'
		c = Classification.find_by_mailbox_and_domain_and_imap_group('%', domain, @account.imap_group) 
	end

	if c.nil?
		c=Classification.new
		c.mailbox=mailbox
		c.domain=domain
		c.imap_group=@account.imap_group
	end

	c.byuser=true

	c.movetolater = (newsymbol == 'l')
	c.blackhole = (newsymbol == 'b')

	c.save

	message_id = find_message_id(envelope.message_id)
	if message_id
		message_id.last_seen=newsymbol
		message_id.save
	end
	dd "Message classification manual change #{oldsymbol}->#{newsymbol}: #{mailbox}@#{domain}" 

end

def train_from_folder(folder, symbol)
	foreach_msg_in_folder(folder, @filter) do |uid, envelope|
		oldsymbol=register_message(uid, envelope, symbol)
		if oldsymbol != symbol
			handle_manual_learn(uid, envelope, oldsymbol, symbol)
		end
	end
end

def folder_check_manual_learn(folder, symbol, delete_after_classification = false)
	@imap.select(folder)
	@imap.expunge
	foreach_msg_in_folder(folder, @filter, (not delete_after_classification)) do |uid, envelope|
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
	folder_check_manual_learn(@imap_config['laterfolder'], 'l', false)
	folder_check_manual_learn(@imap_config['blackholefolder'], 'b', move_messages)
end


def manual_classify(email, symbol)
	mailbox, domain = email.split(/@/)
	c = Classification.find_by_mailbox_and_domain_and_imap_group(mailbox, domain, @imap_config['accountgroup'])
	unless c
		c=Classification.new
		c.mailbox=mailbox
		c.domain=domain
		c.imap_group=@imap_config['accountgroup']
	end
	c.byuser=true
	c.movetolater=symbol_to_movetolater(symbol)
	c.blackhole=symbol_to_blackhole(symbol)
	c.save
end

def list_folders
  @imap.list("", "*")
end

def set_filter(filter)
	@filter = filter
end

def relax_filter
	@filter="OR RECENT SINCE #{Net::IMAP.format_date(Date.yesterday)}"
end

def filter
	@filter
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
		m=find_message_id(message_id)
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
			m.imap_account=@account
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
	  if msg_id
		begin
		  msgs = @imap.fetch(msg_id, ["UID", "ENVELOPE"])
		  if msgs
			msg = msgs[0]
			envelope = msg.attr["ENVELOPE"]
			uid = msg.attr["UID"]
			unless envelope.nil?
				yield uid, envelope
			end
		  end
		rescue Net::IMAP::NoResponseError => e
		  dd "Error: "
		  dd e
		  dd "Note: This usually happens when the message is deleted by other connection before fetching it."
		end
	  end

	end

end

def dd(what)
	puts "#{what}" if DEBUG
end

def de(what)
	puts "#{what}"
end

def known_uid?(uid)
	not SeenUid.find_by_uid_and_imap_account_id(uid, @account.id).nil?
end

def mark_as_seen(uid)
	seen = SeenUid.new
	seen.uid = uid
	seen.imap_account = @account
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

def find_message_id(message_id)
	MessageId.find_by_message_id_and_imap_account_id(message_id, @account.id)
end

def copy_template_rules
	Classification.find_all_by_imap_group('_template').each do |ctempl|
		cl = Classification.new
		cl.mailbox=ctempl.mailbox
		cl.domain=ctempl.domain
		cl.movetolater=ctempl.movetolater
		cl.blackhole=ctempl.blackhole
		cl.imap_group=@imap_config['accountgroup']
		cl.save
	end
	
end


end
