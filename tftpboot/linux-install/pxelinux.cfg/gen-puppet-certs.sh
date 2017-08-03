#!/bin/bash

if [ $# -lt 1 ]; then
  echo Please give a full hostname
  exit
fi


# if needed to remove existing certs
puppetca --clean $1

# to create new cert
mkdir /data/puppet/client/private_keys/ /data/puppet/client/certs/ 
puppetca --generate $1
mv /etc/puppet/ssl/private_keys/$1.pem      /data/puppet/client/private_keys/
mv /etc/puppet/ssl/certs/$1.pem             /data/puppet/client/certs/
chmod 444 /data/puppet/client/private_keys/$1.pem                    
chmod 444 /data/puppet/client/certs/$1.pem

