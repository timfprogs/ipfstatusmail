#!/bin/sh

source /var/ipfire/dma/mail.conf

# Find the old key if there is one so we can delete it later

OLDKEY=`gpg --homedir /var/ipfire/statusmail/certificates --with-colons --fingerprint --list-keys IPFire | sed -ne '/^fpr/{s/fpr//;s/://g;p}'`

echo Generate new keys

/usr/bin/gpg --homedir /var/ipfire/statusmail/certificates --batch --gen-key <<EOF
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
  gpg --homedir /var/ipfire/statusmail/certificates --batch --yes --delete-secret-keys $OLDKEY
  gpg --homedir /var/ipfire/statusmail/certificates --batch --yes --delete-keys $OLDKEY
fi;
