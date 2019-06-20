#! /bin/bash

echo Stopping statusmail from running

rm -f /etc/fcron.hourly/statusmail.sh
rm -f /etc/fcron.hourly/statusmail

echo Removing menu

rm -f /var/ipfire/menu.d/EX-statusmail.menu

echo Removing scripts

rm -rf /var/ipfire/statusmail
rm -rf /usr/lib/statusmail
rm -f /srv/web/ipfire/cgi-bin/statusmail.cgi
rm -f /srv/web/ipfire/html/images/play.png
rm -f /usr/local/bin/statusmail.pl

echo Updating language files

rm -f /var/ipfire/addon-lang/statusmail*

# Update language cache

update-lang-cache
