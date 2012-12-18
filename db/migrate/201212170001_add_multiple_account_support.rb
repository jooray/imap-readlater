class AddMultipleAccountSupport < ActiveRecord::Migration
  def change
	create_table :imap_accounts do |t|
		t.string :login
		t.string :server
		t.string :imap_group

		t.timestamps
	end

	add_column :seen_uids, :imap_account_id, :integer
	add_column :message_ids, :imap_account_id, :integer
	add_column :classifications, :imap_group, :string, :default => 'default'
	add_column :conversations, :imap_group, :string, :default => 'default'
  end


end
