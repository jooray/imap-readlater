class AddDefaultFilters < ActiveRecord::Migration
  
class Classification < ActiveRecord::Base
end

  def up
        domains_for_read_later = [ 'backclick.airberlin.com', 'facebookmail.com', 'facebookappmail.com', 'linkedin.com', 'postmaster.twitter.com' ]
	domains_for_read_later.each do |domain|
		c=Classification.new
		c.mailbox='%'
		c.domain=domain
		c.movetolater=true
		c.blackhole=false
		c.byuser=false
		c.imap_group='_template'
		c.save
	end
  end

  def down
	Classification.where(:imap_group => '_template').destroy_all
  end


end
