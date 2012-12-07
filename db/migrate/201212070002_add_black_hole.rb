class AddBlackHole < ActiveRecord::Migration
  def change
	add_column :classifications, :blackhole, :boolean, :default => false
  end

end
