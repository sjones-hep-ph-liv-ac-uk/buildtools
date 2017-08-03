#!/bin/sh

# Set the path for the other things
. path.sh

# Whether to badblock drives
BADBLOCK=0

# Build these nodes:

WN=' 
r27-n01.ph.liv.ac.uk 
'
#echo $WN

# Make the puppet certs for the machines
#pushd .
#cd /root/scripts

for n in $WN; do
  if [ ! -e /data/puppet/client/private_keys/$n.pem ] || [ ! -e /data/puppet/client/certs/$n.pem ]; then
    echo Certs for $n do not exist, making them
    ./gen-puppet-certs.sh $n
  else
    echo Certs for $n already exist!
  fi
done

#popd

# Now make the links (each node to build gets a "hexlink")
for n in $WN; do
  RACK=`echo $n | cut -d"-" -f 1 | sed "s/r//"`
  NODE=`echo $n | cut -d"n" -f 2 | sed "s/\..*//"`
  which linktool.pl
  linktool.pl -r $RACK  -n $NODE -template  ksBoot.template -ip 132.123 -c /opt/local/linux/SL/buildtools/synctool/dhcpdtab.cfg -b $BADBLOCK
done

ls -lrt C0* 2> /dev/null
if [ $? != 0 ]; then
  echo NO LINKS EXIST
fi

# Sync DHCPD with the links. Use a custom wrapper (-w) so we can put in free text section if we want.
synctool.pl -d . -w /opt/local/linux/SL/buildtools/synctool/dhcpdwrapper.cfg \
   -c /opt/local/linux/SL/buildtools/synctool/dhcpdtab.cfg -o /etc/dhcpd.conf

/sbin/service dhcpd restart

