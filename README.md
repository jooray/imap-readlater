imap-readlater
==============

About
-----

Scans all your e-mail headers (From and To only). For classification, it uses simple algorithm:

For each new e-mail in INBOX, if I got an e-mail from the same sender before and I never replied -> classify as "read later"  
Otherwise -> keep in inbox

Setup
-----

1. Edit at least config/imap.yml. It needs to see your incoming mail folder (archive, backup) and especially your sent folder.
2. run this:
   
	# > db/development.sqlite.db
   
	# rake db:migrate
   
   (including the > at the beginning)
3. run imapfetchheaders.rb to learn, this can take a few hours
4. run "imapclassify.rb -d" after imapfetchheaders finished (otherwise it will learn and remember bad choices) and it will dump on stdout what it thinks about the e-mails in your inbox
5. if you are confident about the results, you can omit the "-d" (dry run), it will move the messages
6. you can run imapfetchheaders.rb from cron with "-r" parameter (once in an hour) to learn from new sent and
    inbox messages. -r will process everything marked as "NEW" by the client and everything since yesterday.

While I can not guarantee your e-mail safety, I ran it on my production e-mail boxes already.

More information
----------------

If someone can recommend me a good list of bulk mailing servers, or have any ideas about filtering
bulk e-mail (newsletters, notifications from social networks, ...), let me know.

TODO
----

TODO: Lots :)
 - List of bulk mailers
 - Learn from moving messages around
 - Implement Black Hole

Copying
-------

Author: Juraj Bednar, see COPYING for license (simplified BSD license)

Pull requests welcome, please contribute!

