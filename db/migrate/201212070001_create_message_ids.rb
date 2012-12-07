class CreateMessageIds < ActiveRecord::Migration
  def up
    create_table :message_ids do |t|
      t.string :message_id
      t.string :last_seen, :default => 'i'
      t.timestamps
    end
  end

  def down
    drop_table :message_ids
  end
end
