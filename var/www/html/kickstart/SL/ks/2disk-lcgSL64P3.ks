reboot
install
url --url http://123.234.178.142/someshare/linux/scientific/6.4/x86_64/os
lang en_US.UTF-8
keyboard uk
skipx
network --device eth0 --bootproto dhcp --ipv6 auto

repo --name="Scientific Linux"  --baseurl=http://123.234.178.142/someshare/linux/scientific/6.4/x86_64/os/ --cost=100
repo --name="Scientific Linux Updates"  --baseurl=http://123.234.178.142/someshare/linux/scientific/6.4/x86_64/updates/security/ --cost=1000

repo --name="DependenciesEl6" --baseurl=http://123.234.178.142/someshare/someshare.puppetlabs.com/el/6/dependencies/x86_64/ --cost=101
repo --name="ProductsEl6"     --baseurl=http://123.234.178.142/someshare/someshare.puppetlabs.com/el/6/products/x86_64/ --cost=100

rootpw --iscrypted ABCDEF
timezone --utc Europe/London
bootloader --location=mbr --driveorder=sda --append="rhgb quiet"

firewall --disabled
selinux --disabled
authconfig --enableshadow --enablemd5

bootloader --location=mbr

zerombr yes
clearpart --all

part raid.1 --size=326545   --ondisk=sda
part raid.2 --size=326545   --ondisk=sdb
part raid.3 --size=412016  --ondisk=sda
part raid.4 --size=412016  --ondisk=sdb
part raid.5 --size=20076   --ondisk=sda
part raid.6 --size=20076   --ondisk=sdb
part raid.7 --size=160169  --ondisk=sda
part raid.8 --size=160169  --ondisk=sdb
part raid.9  --size=16038  --ondisk=sda
part raid.10 --size=16038  --ondisk=sdb

# Make some dummy swap devices (md0, md1) out of partitions
# (this is fast, and will get overwritten with an xfs file system).
# This will be RAID 0 (striped).
raid swap --fstype swap --level=RAID0 --device md0 raid.1 raid.2
raid swap --fstype swap --level=RAID0 --device md1 raid.3 raid.4
# Format other filesystems as RAID0 as there is no reliability
# gain with RAID1 if the critical data partitions are RAID0 anyway
raid / --fstype ext3 --level=RAID1 --device md2 raid.5 raid.6
raid /var --fstype ext3 --level=RAID0 --device md3 raid.7 raid.8
raid swap --fstype swap --level=RAID0 --device md4 raid.9 raid.10

%packages
@base
@client-mgmt-tools
@console-internet
@core
@debugging
@directory-client
@mail-server
@hardware-monitoring
@java-platform
@large-systems
@nfs-file-server
@network-file-system-client
@network-tools
@performance
@perl-runtime
@system-management-snmp
@scalable-file-systems
@server-platform
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
xorg-x11-fonts-Type1
shared-mime-info
GConf2
pcsc-lite-libs 
puppet
-dovecot
-spamassassin
-yum-autoupdate
-systemtap-runtime
-yum-conf-sl6x-1-2.noarch

%pre

grep "badblock=1" /proc/cmdline > /dev/null
if [ $? == 0 ]; then
  echo Do badblock
  badblocks -fw -t 0x89abcdef -c 65536 /dev/sda
  badblocks -fw -t 0x89abcdef -c 65536 /dev/sdb
  badblocks -fw -t 0x89abcdef -c 65536 /dev/sdc
else
  echo Doing no badblock
fi

%post

(
#--------------------------------------------------------------
# Get rid of some troublesome Yum repos
#
# 18.02.14 sj
#--------------------------------------------------------------

rm /etc/someshare.repos.d/sl6x.repo
rm /etc/someshare.repos.d/sl.repo
yum clean all

#--------------------------------------------------------------
# Add DPM someuser group and account to ensure consistent uid/gid
#
# 15.07.10 jb
#--------------------------------------------------------------
/usr/sbin/groupadd -g 104 someuser
/usr/sbin/useradd -c "DPM user" -d /home/someuser -g 104 -m -n -s /bin/bash -u 104 someuser

#--------------------------------------------------------------
# Add someuser2 group to avoid clashes
#
# 02.10.15 sj
#--------------------------------------------------------------
/usr/sbin/groupadd -g 804 someuser2

#---------------------------------------------
# A kickstart component to add a temporary host file.
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
echo "123.234.178.142 someserver.ph.liv.ac.uk"                       >> /etc/hosts
echo "123.222.50.101  test-server.ph.liv.ac.uk"                >> /etc/hosts
echo ""                                                        >> /etc/hosts

#---------------------------------------------
# A kickstart component to set services.
# 29.01.09, sj
#---------------------------------------------
echo set services               >> /tmp/kslog.txt
#---------------------------------------------
/sbin/chkconfig acpid on
/sbin/chkconfig cups off
/sbin/chkconfig mdmonitor on
/sbin/chkconfig --add postfix
/sbin/chkconfig postfix on
/sbin/chkconfig sysstat on

#---------------------------------------------
# A kickstart component to reset a hex link,
# telling the system that a certain node has been 
# rebuilt.
# 29.01.09, sj
#---------------------------------------------
echo reset a hex link           >> /tmp/kslog.txt
# Make a temporary mnt point, and mnt PXE config dir
mkdir  /tmp/kick
mount -o rw,nolock 123.222.178.142:/tftpboot/linux-install/pxelinux.cfg /tmp/kick


# Run some perl to parse the file and make the hex ip 
perl << "XXXX"

  # Open the file with the IP address in it
  #open  (IPADDR,"/tmp/kick/ipaddr.txt") or die("Read of IP file failed\n");
  $status = open  (IPADDR,"/sbin/ifconfig eth0 | grep 'inet addr:' | cut -d: -f2 | awk '{ print $1}'|");
  if ($status == 0) {
    # Could not get the IP
    while(1) { 
      system ("echo Read of IP file failed. Hung. >> /tmp/kslog.txt") ; sleep(10); 
    }
  }


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
  }
  close (IPADDR);

  # Check there was one IP line
  if ($count != 1) {
    # Something failed.
    while(1) { 
      system ("echo No IP could be determined. Hung. >> /tmp/kslog.txt") ; sleep(10); 
    }
  }
XXXX

# Unmnt and get rid of the mnt point
umount /tmp/kick
rmdir /tmp/kick

#---------------------------------------------
# A kickstart component for copying and installing
# various scripts, files and crons. Also installs
# the network parts, and some keys.
#
# 29.01.09, sj
#---------------------------------------------
echo installing various scripts  >> /tmp/kslog.txt
#---------------------------------------------
# mnt directory containing scripts and configuration files
mkdir /tmp/scripts
mount -o nolock someserver.ph.liv.ac.uk:/data/ks_scripts /tmp/scripts

# run network configuration script
/tmp/scripts/inetadr-eth0.sh

# copy prelinking configuration file over (disables prelinking)
cp -f /tmp/scripts/prelink /etc/sysconfig/prelink

# copy across resolv.conf
cp /tmp/scripts/resolv.conf /etc/resolv.conf

# copy across standard ssh server host keys
cp /tmp/scripts/ssh.tar /etc
pushd .
cd /etc
rm -rf ssh
tar -xvf ssh.tar
rm ssh.tar
popd

# Install the files
mkdir /root/bin
chmod 755 /root/bin

# unmnt scripts scripts/files directory
umount /tmp/scripts
rmdir  /tmp/scripts

#---------------------------------------------
# A kickstart component to do yum update
#
# Yum itself is not updated, due to certain problems
# with dependencies.
#
# 29.01.09, sj
#---------------------------------------------
echo yum update                 >> /tmp/kslog.txt
#---------------------------------------------

yum clean all

# add a temp yum.conf file, with the errata repository
cat > /etc/someshare.conf.initupdate << HEREDOC1
[main]
cachedir=/var/cache/someshare
logfile=/var/log/someshare.log
pluginpath=/usr/lib/someshare-plugins/
debuglevel=2
distroverpkg=redhat-release
metadata_expire=43200
tolerant=1
exactarch=1
plugins=1
# this set is borrowed from the DELLs
#exclude=kernel,kernel-smp,kernel-devel,kernel-smp-devel,yum,yum-conf
exclude=yum,yum-conf

# PUT YOUR REPOS HERE OR IN separate files named file.repo
# in /etc/someshare.repos.d
[sl-updates]
name=SL 6 updates
baseurl=http://someserver.ph.liv.ac.uk//someshare/linux/scientific/6.4/x86_64/updates/security
enabled=1
gpgcheck=0
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-csieh file:///etc/pki/rpm-gpg/RPM-GPG-KEY-dawson file:///etc/pki/rpm-gpg/RPM-GPG-KEY-jpolok file:///etc/pki/rpm-gpg/RPM-GPG-KEY-cern

HEREDOC1

echo Do Yum Update
mv /etc/someshare.repos.d/sl.repo /tmp
mv /etc/someshare.repos.d/sl-other.repo /tmp
yum update -y -c /etc/someshare.conf.initupdate
yum clean all

echo Done With Yum 
#---------------------------------------------
# A kickstart component to setup puppet on a node.
# 29.01.09, sj
#---------------------------------------------
echo setting up puppet                     >> /tmp/kslog.txt

echo "NOZEROCONF=yes" >> /etc/sysconfig/network


MYHOSTNAME=`grep HOSTNAME /etc/sysconfig/network | cut -d= -f2`
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
#--------------------------------------------------------------
# Format data RAID array with XFS
#--------------------------------------------------------------

swapoff /dev/md0
swapoff /dev/md1
mkfs.xfs -d su=512k,sw=2 -L data -f /dev/md0
mkfs.xfs -d su=512k,sw=2 -L data2 -f /dev/md1
mkdir /data
mkdir /data2
sed '/md0/d' /etc/fstab > /etc/fstab.new
echo "/dev/md0	/data	xfs	defaults,noatime,logbufs=8 1 2" >> /etc/fstab.new
mv /etc/fstab.new /etc/fstab

sed '/md1/d' /etc/fstab > /etc/fstab.new
echo "/dev/md1  /data2   xfs     defaults,noatime,logbufs=8 1 2" >> /etc/fstab.new
mv /etc/fstab.new /etc/fstab

mount -t xfs /dev/md0 /data
mount -t xfs /dev/md1 /data2

mkdir -p /data/var/spool/
rsync -av --delete /var/spool/ /data/var/spool/
rm -rf /var/spool/
ln -sf /data/var/spool/ /var/spool

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

echo "# MDADM config written by custom kickstart script" > /etc/mdadm.conf
echo "DEVICE partitions" >> /etc/mdadm.conf
echo "MAILADDR raidadmin@abc.def.com" >> /etc/mdadm.conf
/sbin/mdadm --detail --scan >> /etc/mdadm.conf

sleep 5 

echo end of post install      >> /tmp/kslog.txt

) > /root/kickstart-install.log 2>&1

# END OF KICKSTART
