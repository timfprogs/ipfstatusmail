#!/bin/sh

############################################################################
#                                                                          #
# Send log and status emails for IPFire                                    #
#                                                                          #
# This is free software; you can redistribute it and/or modify             #
# it under the terms of the GNU General Public License as published by     #
# the Free Software Foundation; either version 3 of the License, or        #
# (at your option) any later version.                                      #
#                                                                          #
# This is distributed in the hope that it will be useful,                  #
# but WITHOUT ANY WARRANTY; without even the implied warranty of           #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
# GNU General Public License for more details.                             #
#                                                                          #
# You should have received a copy of the GNU General Public License        #
# along with IPFire; if not, write to the Free Software                    #
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA #
#                                                                          #
# Copyright (C) 2018 - 2019 The IPFire Team                                #
#                                                                          #
############################################################################
# Generates a PGP key that is used to sign email messages                  #
############################################################################

source /var/ipfire/dma/mail.conf

# Find the old key if there is one so we can delete it later

OLDKEY=`gpg --homedir /var/ipfire/statusmail/keys --with-colons --fingerprint --list-keys IPFire | sed -ne '/^fpr/{s/fpr//;s/://g;p}'` 2>/dev/null

echo Generate new keys

/usr/bin/gpg --homedir /var/ipfire/statusmail/keys --batch --gen-key <<EOF
Key-Type: rsa
Key-Length: 4096
Key-Usage: sign
Name-Real: IPFire
Name-Email: $SENDER
Expire-Date: 0
Passphrase: ipfirestatusemail
%commit
%echo done
EOF

if [[ $OLDKEY ]]; then
  echo Delete old keys
  gpg --homedir /var/ipfire/statusmail/keys --batch --yes --delete-secret-keys $OLDKEY
  gpg --homedir /var/ipfire/statusmail/keys --batch --yes --delete-keys $OLDKEY
fi;
