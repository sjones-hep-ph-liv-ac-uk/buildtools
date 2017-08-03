#!/bin/sh

. path.sh

linktool.pl -t  ksBoot.template -ip 192.168.50.1 -c /opt/local/linux/SL4_4/buildtools/synctool/dhcpdtab.cfg
linktool.pl -t  ksBoot.template -ip 192.168.50.2 -c /opt/local/linux/SL4_4/buildtools/synctool/dhcpdtab.cfg

ls -lrt C0*
synctool.pl -d . -t /opt/local/linux/SL4_4/buildtools/synctool/dhcpdtab.cfg -o /etc/dhcpd.conf

service dhcpd restart

