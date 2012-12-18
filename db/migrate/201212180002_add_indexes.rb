class AddIndexes < ActiveRecord::Migration
  

  def change
	add_index :classifications, :imap_group
	add_index :classifications, :mailbox
	add_index :classifications, :domain
	add_index :conversations, :imap_group
	add_index :conversations, :frommailbox
	add_index :conversations, :fromdomain
	add_index :conversations, :tomailbox
	add_index :conversations, :todomain
	add_index :message_ids, :imap_account_id
	add_index :message_ids, :message_id
	add_index :seen_uids, :uid
  end


end
