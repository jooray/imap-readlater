imap-readlater
==============

About
-----

Scans all your e-mail headers (From and To only). For classification, it uses simple algorithm:

For each new e-mail in INBOX, if I got an e-mail from the same sender before and I never replied -> classify as "read later"  
Otherwise -> keep in inbox

It uses two special folders (it will create them), default names used, can be changed in config:
 - @Later - if the above mentioned simple algorithm thinks it's for later, it will put the mail here
 - @Blackhole - if you put a mail here, you will never get any more mail from the same sender

You can move messages between @Later, @Blackhole and INBOX and it will learn it's new classification and will work
correctly. So if it put an e-mail you wanted in your INBOX into @Later, just dragging it to INBOX and running
imapclassify.rb will do the trick. Works the other way around too. If you accidentally put something into @Blackhole,
correct this problem using manualclassify.rb (run it to see help).

I was inspired by an excellent service called SaneBox. Although I love the service and would even pay for it, I can not give access to my e-mail to a third party for contractual reasons (and it would be difficult to let them reach my inbox anyway), I decided to do a much simpler version myself. I am still fan of SaneBox.

Setup
-----

1. Check prerequisities, we need activesupport, activerecord and sqlite3 (yes, I should learn to use bundler)
2. Edit at least config/imap.yml. It needs to see your incoming mail folder (archive, backup) and especially your sent folder.
3. run this:
   
	touch db/development.sqlite.db ; rake db:migrate
   
4. run imapfetchheaders.rb to learn, this can take a few hours
5. run "imapclassify.rb -d" after imapfetchheaders finished (otherwise it will learn and remember bad choices) and it will dump on stdout what it thinks about the e-mails in your inbox
6. if you are confident about the results, you can omit the "-d" (dry run), it will move the messages
7. you can run imapfetchheaders.rb from cron with "-r" parameter (cca once in an hour) to learn from new sent and
    inbox messages. -r will process everything marked as "NEW" by the client and everything since yesterday.

I put this to my crontab (make sure that ruby points to the right ruby, you may have different environment)

	*/2 * * * * (cd ~/imap-readlater ; ruby imapclassify.rb) >> ~/.imap-readlater.log 2>&1  
	03,33 * * * * (cd ~/imap-readlater ; ruby imapclassify.rb && ruby imapfetchheaders.rb -r) >> ~/.imap-readlater.log 2>&1

While I can not guarantee your e-mail safety, I run this on my production mailboxes already. As far as I know it does
not eat my e-mail. YMMV.

More information
----------------

If someone can recommend me a good list of bulk mailing servers, or have any ideas about filtering
bulk e-mail (newsletters, notifications from social networks, ...), let me know.

TODO
----

TODO: Lots :)
 - List of bulk mailers
 - Implement multiple account support (move imap.yml to configuration.yml, merge database config there, add command line option for choosing current configuration)

Copying
-------

Author: Juraj Bednar, see COPYING for license (simplified BSD license)

Pull requests welcome, please contribute!

