class CreateSeenUids < ActiveRecord::Migration
  def up
    create_table :seen_uids do |t|
      t.string :uid
      t.timestamps
    end
  end

  def down
    drop_table :seen_uids
  end
end
