class CreateTables < ActiveRecord::Migration
  def up
    create_table :conversations do |t|
      t.string :frommailbox
      t.string :fromdomain
      t.string :tomailbox
      t.string :todomain
      t.integer :conversations
      
      t.timestamps
    end
    create_table :classifications do |t|
      t.string :mailbox
      t.string :domain
      t.boolean :byuser
      t.boolean :movetolater
      
      t.timestamps
    end
  end

  def down
    drop_table :conversations
    drop_table :classifications
  end
end
