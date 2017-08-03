auth --enableshadow --passalgo=sha512
install
url --url="http://123.222.178.142/someshare/centos/7.3/os/x86_64/"
repo --name="CentoS_Seven" --baseurl=http://123.234.178.141/someshare/centos/7.3/os/x86_64/ --cost=100
repo --name="CentoS_Seven_updates" --baseurl=http://123.234.178.141/someshare/centos/7.3/updates/x86_64/ --cost=1000
repo --name="DependenciesEl7" --baseurl=http://123.234.178.142/someshare/someshare.puppetlabs.com/el/7/dependencies/x86_64/ --cost=101
repo --name="ProductsEl7" --baseurl=http://123.234.178.142/someshare/someshare.puppetlabs.com/el/7/products/x86_64/ --cost=100
graphical
firewall --disabled
firstboot --disable
ignoredisk --only-use=sda,sdb,sdc
keyboard --vckeymap=uk --xlayouts='gb'
lang en_GB.UTF-8

network  --bootproto=dhcp --device=enp5s0 --onboot=off --ipv6=auto --no-activate
network  --bootproto=dhcp --device=enp6s0 --ipv6=auto --activate
network  --hostname=localhost.localdomain
reboot

rootpw --iscrypted ABCDEF
selinux --disabled
services --enabled="chronyd"
timezone Europe/London --isUtc
bootloader --append="rhgb quiet crashkernel=auto" --location=mbr --driveorder="sda" --boot-drive=sda

clearpart --all
part / --fstype="xfs" --ondisk=sda --size=20000
part /var --fstype="xfs" --ondisk=sda --size=30000
part swap --fstype="swap" --ondisk=sda --size=16000

part raid.1 --fstype="mdmember" --ondisk=sdc --size=783868
part raid.2 --fstype="mdmember" --ondisk=sdb --size=783868
part raid.3 --fstype="mdmember" --ondisk=sdc --size=170000
part raid.4 --fstype="mdmember" --ondisk=sdb --size=170000

raid /data --device=0 --fstype="xfs" --level=RAID0 raid.2 raid.1
raid /data2 --device=1 --fstype="xfs" --level=RAID0 raid.4 raid.3

%packages
@base
@console-internet
@core
@debugging
@directory-client
@mail-server
@hardware-monitoring
@java-platform
@large-systems
@network-file-system-client
@network-tools
@performance
@perl-runtime
@system-admin-tools
ruby
oddjob
sgpio
pax
certmonger
pam_krb5
krb5-workstation
wireshark
perl-DBD-SQLite
puppet
-dovecot
-spamassassin
-yum-autoupdate
-systemtap-runtime

%end

%pre

grep "badblock=1" /proc/cmdline > /dev/null
if [ $? == 0 ]; then
  echo Would do badblock here
  badblocks -fw -t 0x89abcdef -c 65536 /dev/sda
  badblocks -fw -t 0x89abcdef -c 65536 /dev/sdb
  badblocks -fw -t 0x89abcdef -c 65536 /dev/sdc
else
  echo Doing no badblock here
fi
%end

%post

(

#--------------------------------------------------------------
# Get rid of some odd repos and modify the others to suit setup here
#
# 04.01.16 sj
#--------------------------------------------------------------
yum clean all
cd /etc/someshare.repos.d
sed -i \
   -e "s/^mirrorlist/#mirrorlist/" \
   -e "s/\#baseurl/baseurl/" \
   -e "s/http:\/\/mirror.centos.org\/centos\/\$releasever/http:\/\/123.234.178.141\/someshare\/centos\/7.3/" \
     CentOS-Base.repo CentOS-CR.repo
yum update

#--------------------------------------------------------------
# Add DPM someuser group and account to ensure consistent uid/gid
#
# 15.07.10 jb
#--------------------------------------------------------------
echo add someuser group >> /tmp/kslog.txt
#--------------------------------------------------------------
/usr/sbin/groupadd -g 104 someuser
/usr/sbin/useradd -c "DPM user" -d /home/someuser -g 104 -m -n -s /bin/bash -u 104 someuser

#---------------------------------------------
# Add a temporary host file.
#
# 29.01.09, sj
#---------------------------------------------
echo add a temporary host file  >> /tmp/kslog.txt
#---------------------------------------------
# add a temporary hosts file
echo "# TEMP FILE ADDED BY KICKSTART                         " >  /etc/hosts
echo "127.0.0.1  localhost.localdomain localhost" >> /etc/hosts
echo ""                                                        >> /etc/hosts
echo "123.234.178.142 someserver.ph.liv.ac.uk"                >> /etc/hosts
echo "123.234.178.141 someserver.ph.liv.ac.uk"                       >> /etc/hosts
echo "123.234.48.110  vo10.ph.liv.ac.uk"                       >> /etc/hosts
echo "123.234.48.98   mike.ph.liv.ac.uk"                       >> /etc/hosts


#---------------------------------------------
# Copying and installing various scripts, files and 
# crons. Also installs network parts, and some keys.
#
# 29.01.09, sj
#---------------------------------------------
echo installing various scripts  >> /tmp/kslog.txt
#---------------------------------------------
# mnt directory containing scripts and configuration files
mkdir /tmp/scripts
mount -o nolock 123.234.178.141:/data/ks_scripts /tmp/scripts

# copy prelinking configuration file over (disables prelinking)
cp -f /tmp/scripts/prelink /etc/sysconfig/prelink

# copy across standard ssh server host keys
cp /tmp/scripts/ssh.tar /etc
pushd .
cd /etc
rm -rf ssh
tar -xvf ssh.tar
rm ssh.tar
popd

# unmnt scripts scripts/files directory
umount /tmp/scripts
rmdir  /tmp/scripts


#---------------------------------------------
# A kickstart component to reset a hex link,
# telling the system that a certain node has been
# rebuilt.
# 29.01.09, sj
#---------------------------------------------
echo try reset a hex link           >> /tmp/kslog.txt
# Make a temporary mnt point, and mnt PXE config dir
mkdir  /tmp/kick
mount -o rw,nolock 123.222.178.142:/tftpboot/linux-install/pxelinux.cfg /tmp/kick

# Run some perl to parse the file and make the hex ip
perl << "XXXX"

  # Open the file with the IP address in it
  #open  (IPADDR,"/tmp/kick/ipaddr.txt") or die("Read of IP file failed\n");
  $status = open  (IPADDR,"/sbin/ifconfig enp6s0 | grep \' inet \' | sed -e \"s/.*inet //\" -e \"s/netmask.*//\" | awk '{ print $1}'|");
  if ($status == 0) {
    # Could not get the IP
    while(1) {
      system ("echo Read of IP file failed. Hung. >> /tmp/kslog.txt") ; sleep(10);
    }
  }
  system ("echo Read of IP file worked ok >> /tmp/kslog.txt") ; 

  # Go over the file (there should be one line) getting the ip address
  $hexIp = "";
  $count = 0;
  while(<IPADDR>) {
    $line = $_;
    chomp($line);
    $count++;

    # Get the part with the ip address
    $line =~ m/(\d+\.\d+\.\d+\.\d+)/;
    if (!defined($&)) {
      while(1) {
        system ("echo IP Format wrong. Hung. >> /tmp/kslog.txt") ; sleep(10);
      }
    }
    system ("echo IP Format OK >> /tmp/kslog.txt") ; 

    # Create the hex ip
    $hexIp = sprintf("%02X%02X%02X%02X",split('\.',$1));

    # Link the hex ip to the hard drive boot process. This
    # stops the boot from cycling around forever.
    $status = system("(cd /tmp/kick; ln -sf hdBoot.cfg $hexIp)");
    if ($status != 0) {
      # Something failed.
      while(1) {
        system ("echo Could not stop boot cycle. Hung. >> /tmp/kslog.txt") ; sleep(10);
      }
    }
    system ("echo try to stop boot cycle worked used  $hexIp >> /tmp/kslog.txt") ; 
  }
  close (IPADDR);

  # Check there was one IP line
  if ($count != 1) {
    # Something failed.
    while(1) {
      system ("echo No IP could be determined. Hung. >> /tmp/kslog.txt") ; sleep(10);
    }
  }
  system ("echo got an ip address >> /tmp/kslog.txt") ; 
XXXX

# Unmnt and get rid of the mnt point
umount /tmp/kick
rmdir /tmp/kick


#---------------------------------------------
# Set up the network
# 18.05.17, sj
#---------------------------------------------

# Set HOSTNAME
HOSTNAME=`ifconfig | perl -lane 'if (/inet 123.222.(\S+)/) {@bits=split(/\./,$1); printf("r%02d-n%02d.ph.liv.ac.uk", $bits[0],$bits[1])} ; '`
hostnamectl set-hostname $HOSTNAME
echo $HOSTNAME > /etc/hostname

# So some debug logging
#echo HOSTNAME $HOSTNAME >> /tmp/kslog.txt
#ifconfig >> /tmp/kslog.txt
#echo print content of hostname >> /tmp/kslog.txt
#cat /etc/hostname >> /tmp/kslog.txt
#echo printed hostname >> /tmp/kslog.txt

# Set up the network file, for the GATEWAY etc.
rm -f /etc/sysconfig/network; touch /etc/sysconfig/network
HOSTNAME=`ifconfig | perl -lane 'if (/inet 123.222.(\S+)/) {@bits=split(/\./,$1); printf("r%02d-n%02d.ph.liv.ac.uk", $bits[0],$bits[1])} ; '`
echo NOZEROCONF=yes     >> /etc/sysconfig/network
echo NETWORKING=yes     >> /etc/sysconfig/network
echo HOSTNAME=$HOSTNAME >> /etc/sysconfig/network
echo ` ifconfig | perl -lane 'if (/inet 123.222.(\S+)/) {@bits=split(/\./,$1); printf("GATEWAY=123.222.%d.254\n", $bits[0])} ; '` >> /etc/sysconfig/network

# Fix the ip to static
sed -i -e "s/IPV6/#IPV6/" -e "s/BOOTPROTO=\"dhcp\"/BOOTPROTO=\"static\"/" /etc/sysconfig/network-scripts/ifcfg-enp6s0

echo ` ifconfig | perl -lane 'if (/inet 123.222.(\S+)/) {@bits=split(/\./,$1); printf("IPADDR=123.222.%d.%d\n", $bits[0],$bits[1])} ; '` >> /etc/sysconfig/network-scripts/ifcfg-enp6s0
echo PREFIX=24 >> /etc/sysconfig/network-scripts/ifcfg-enp6s0

#---------------------------------------------
# Set services.
# 29.01.09, sj
#---------------------------------------------
echo set services               >> /tmp/kslog.txt
#---------------------------------------------
# switch services on/off
/sbin/chkconfig acpid on
/sbin/chkconfig gpm off
/sbin/chkconfig isdn off
/sbin/chkconfig mdmonitor on
/sbin/chkconfig --add postfix
/sbin/chkconfig postfix on
/sbin/chkconfig sendmail off
/sbin/chkconfig xinetd off
/sbin/chkconfig sysstat on
/sbin/chkconfig bluetooth off
/sbin/chkconfig pcscd off
/sbin/chkconfig atd off
/sbin/chkconfig puppet on
/sbin/chkconfig firewalld on

#---------------
# Enable ssh in the firewall
/sbin/service firewalld restart
/usr/bin/firewall-cmd --permanent --add-service=ssh
/sbin/service firewalld restart

#---------------------------------------------
# Mount the data dirs
# 15.03/17, sj
#---------------------------------------------
mkdir /data
mkdir /data2
mount -t xfs /dev/md0 /data
mount -t xfs /dev/md1 /data2

#---------------------------------------------
# A kickstart component to setup puppet on a node.
# 15.03.17, sj
#---------------------------------------------
echo setting up puppet                     >> /tmp/kslog.txt

echo "NOZEROCONF=yes" >> /etc/sysconfig/network

MYHOSTNAME=`ifconfig | perl -lane 'if (/inet 123.222.(\S+)/) {@bits=split(/\./,$1); printf("r%02d-n%02d.ph.liv.ac.uk", $bits[0],$bits[1])} ; '`
echo MYHOSTNAME $MYHOSTNAME                >> /tmp/kslog.txt

# Copy Puppet certs and enable on bootup
mkdir /tmp/somedir
mount -o nolock vo10.ph.liv.ac.uk:/data/somedir/mike /tmp/somedir/

mkdir -p /var/lib/somedir/ssl/certs
mkdir /var/lib/somedir/ssl/private_keys
chmod 771 /var/lib/somedir/ssl
chmod 755 /var/lib/somedir/ssl/certs
chmod 750 /var/lib/somedir/ssl/private_keys
/bin/cp -f /tmp/somedir/certs/ca.pem /var/lib/somedir/ssl/certs/

certlocation=/var/lib/somedir/ssl/certs/$MYHOSTNAME.pem
privkeylocation=/var/lib/somedir/ssl/private_keys/$MYHOSTNAME.pem

echo Initial cert and key checks           .... >> /tmp/kslog.txt
ls -lrt $certlocation $privkeylocation >> /tmp/kslog.txt
echo Checking if cert $certlocation exists .... >> /tmp/kslog.txt
if [ -e $certlocation ]; then
  echo Cert $certlocation exists, and here is its checksum:     >> /tmp/kslog.txt
  openssl x509 -noout -modulus -in $certlocation | openssl md5  >> /tmp/kslog.txt
fi

echo Checking if privkey $privkeylocation exists .... >> /tmp/kslog.txt
if [ -e $privkeylocation ]; then
  echo Privkey $privkeylocation exists, and here is its checksum:  >> /tmp/kslog.txt
  openssl rsa -noout -modulus -in  $privkeylocation | openssl md5  >> /tmp/kslog.txt
fi

/bin/cp -f /tmp/somedir/certs/$MYHOSTNAME.pem $certlocation
/bin/cp -f /tmp/somedir/private_keys/$MYHOSTNAME.pem $privkeylocation

chmod 644 /var/lib/somedir/ssl/certs/$MYHOSTNAME.pem
chmod 600 /var/lib/somedir/ssl/private_keys/$MYHOSTNAME.pem

# Add initial puppet config so it uses mike as server
mkdir /etc/somedir
/bin/cp /tmp/somedir/somedir-mike.conf-centos7 /etc/somedir/somedir.conf
chkconfig puppet on

echo Final cert and key checks           ....   >> /tmp/kslog.txt
ls -lrt $certlocation $privkeylocation          >> /tmp/kslog.txt
echo Checking if cert $certlocation exists .... >> /tmp/kslog.txt
if [ -e $certlocation ]; then
  echo Cert $certlocation exists, and here is its checksum:     >> /tmp/kslog.txt
  openssl x509 -noout -modulus -in $certlocation | openssl md5  >> /tmp/kslog.txt
fi

echo Checking if privkey $privkeylocation exists .... >> /tmp/kslog.txt
if [ -e $privkeylocation ]; then
  echo Privkey $privkeylocation exists, and here is its checksum:  >> /tmp/kslog.txt
  openssl rsa -noout -modulus -in  $privkeylocation | openssl md5  >> /tmp/kslog.txt
fi

umount /tmp/somedir
rmdir /tmp/somedir

#-----------------------------------------
# Set dns resolver
echo "search ph.liv.ac.uk" > /etc/resolv.conf
echo "nameserver 123.234.110.103" >> /etc/resolv.conf
echo "nameserver 123.234.110.104" >> /etc/resolv.conf

#-----------------------------------------
# Kill the yum auto update
if [ -e /etc/cron.hourly/someshare-autoupdate ] || [ -e /etc/cron.hourly/someshare ] || [ -e /etc/cron.daily/someshare.cron ];then
  echo "++++++++++++++++++++++++++++++++++++++++++++++++"
  echo "Yum cron jobs are now disabled"
  rm -f /etc/cron.hourly/someshare-autoupdate
  rm -f /etc/cron.hourly/someshare
  rm -f /etc/cron.daily/someshare.cron
fi

yum_status=`chkconfig --list |grep yum |grep "3:on"`
service_name=`chkconfig --list |grep yum | cut -f 1`

for serv in $service_name; do

  if [ "x$yum_status" != "x" ]; then
    echo "++++++++++++++++++++++++++++++++++++++++++++++++"
    echo "+ $serv has been switched to off"
    chkconfig $serv off
  fi

  if [ -e /var/lock/subsys/$serv ]; then
     /etc/init.d/$serv stop
  fi
  echo "Done $serv"

done
# Fix the permissions on nsswitch!
chmod 644 /etc/nsswitch.conf

yum clean all

sleep 5

echo end of post install      >> /tmp/kslog.txt

)

%end

