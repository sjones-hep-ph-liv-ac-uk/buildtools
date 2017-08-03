#!/bin/sh

if [ $# != 1 ]; then
  echo Pleave give a full node name
  exit
fi

rm /data/puppet/client/private_keys/$1.pem /data/puppet/client/certs/$1.pem
puppetca --clean $1

puppetca --generate $1
mv /etc/puppet/ssl/private_keys/$1.pem      /data/puppet/client/private_keys/
mv /etc/puppet/ssl/certs/$1.pem             /data/puppet/client/certs/
chmod 444 /data/puppet/client/private_keys/$1.pem                    
chmod 444 /data/puppet/client/certs/$1.pem


  

