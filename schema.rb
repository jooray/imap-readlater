require './database_configuration'

class Conversation < ActiveRecord::Base
end

class Classification < ActiveRecord::Base
end

class SeenUid < ActiveRecord::Base
	belongs_to :imap_account
end

class MessageId < ActiveRecord::Base
	belongs_to :imap_account
end

class ImapAccount < ActiveRecord::Base
	has_many :seen_uids
	has_many :message_ids
end


