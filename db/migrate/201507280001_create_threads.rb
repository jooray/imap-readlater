class CreateThreads < ActiveRecord::Migration
  def up
    create_table :threads do |t|
	    t.boolean :snooze
	    t.integer :imap_account_id
			t.timestamps null: false
    end
    create_table :thread_messages do |t|
      t.integer :thread_id
	    t.string :message_header_id
			t.timestamps null: false
    end
		add_index :threads, :imap_account_id
		add_index :thread_messages, :thread_id
		add_index :thread_messages, :message_header_id
  end

  def down
    drop_table :threads
  end
end
