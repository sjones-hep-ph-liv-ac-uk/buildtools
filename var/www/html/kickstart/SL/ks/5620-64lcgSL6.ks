reboot
install
url --url http://123.234.178.142/someshare/linux/scientific/6.4/x86_64/os
lang en_US.UTF-8
keyboard uk
skipx
network --device eth0 --bootproto dhcp --ipv6 auto

rootpw --iscrypted ABCDEF
timezone --utc Europe/London
bootloader --location=mbr --driveorder=sda --append="rhgb quiet"

firewall --disabled
selinux --disabled
authconfig --enableshadow --enablemd5

bootloader --location=mbr

zerombr yes
clearpart --all

part raid.1 --size=376545   --ondisk=sda
part raid.2 --size=376545   --ondisk=sdb
part raid.3 --size=482016  --ondisk=sda
part raid.4 --size=482016  --ondisk=sdb
part raid.5 --size=20076   --ondisk=sda
part raid.6 --size=20076   --ondisk=sdb
part raid.7 --size=40169   --ondisk=sda
part raid.8 --size=40169   --ondisk=sdb
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
lksctp-tools
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
-dovecot
-spamassassin
-yum-autoupdate
-systemtap-runtime

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
# switch services on/off
# SL5 grubmbled about this
# /sbin/chkconfig apmd off
/sbin/chkconfig acpid off
/sbin/chkconfig cups off
/sbin/chkconfig mdmonitor on
/sbin/chkconfig --add postfix
/sbin/chkconfig postfix on
/sbin/chkconfig sysstat on
/sbin/chkconfig puppet on

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

# Install the cron entries
echo "# Kickstart " > /var/spool/cron/root
echo "# Puppet Name: restart_puppet"                       >> /var/spool/cron/root
echo "*/30 * * * * /root/bin/restart_puppet.sh"            >> /var/spool/cron/root
chmod 600 /var/spool/cron/root

# Install the files
mkdir /root/bin
chmod 755 /root/bin
cp /tmp/scripts/restart_puppet.sh /root/bin/restart_puppet.sh

chmod 755 /root/bin/restart_puppet.sh


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
#exclude=yum,yum-conf

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
mv /etc/someshare.repos.d/sl-other.repo /tmp
mv /etc/someshare.repos.d/sl.repo /tmp
yum update -y -c /etc/someshare.conf.initupdate
yum clean all

echo Post install puppet

echo Done With Yum 
#---------------------------------------------
# A kickstart component to setup puppet on a
# node.
# 29.01.09, sj
#---------------------------------------------
echo puppet                     >> /tmp/kslog.txt
#---------------------------------------------
# install puppet
# mnt puppet install directory
mkdir /tmp/somedir
# This is the new someserver, which is colocated with someserver
mount -o nolock someserver.ph.liv.ac.uk:/data/somedir/client /tmp/somedir/

# install facter and puppet

rpm -ivh /tmp/somedir/facter-1.5.2-1.x86_64.rpm
rpm -ivh /tmp/somedir/augeas-libs-0.10.0-3.el5.x86_64.rpm
rpm -ivh /tmp/somedir/ruby-augeas-0.4.1-1.el6.x86_64.rpm
rpm -ivh /tmp/somedir/ruby-shadow-1.4.1-13.el6.x86_64.rpm
rpm -ivh /tmp/somedir/libselinux-ruby-2.0.94-5.3.el6.x86_64.rpm
rpm -ivh /tmp/somedir/somedir-2.7.22-1.el6.noarch.rpm

HOSTNAME=`grep HOSTNAME /etc/sysconfig/network | cut -d= -f2`

#---------------------------------------------
# copy across pre-generated puppet certificate
mkdir -p /etc/somedir/ssl/certs
mkdir /etc/somedir/ssl/private_keys
chmod 771 /etc/somedir/ssl
chmod 755 /etc/somedir/ssl/certs
chmod 750 /etc/somedir/ssl/private_keys
cp /tmp/somedir/certs/ca.pem /etc/somedir/ssl/certs/
cp /tmp/somedir/certs/$HOSTNAME.pem /etc/somedir/ssl/certs/
cp /tmp/somedir/private_keys/$HOSTNAME.pem /etc/somedir/ssl/private_keys/
chmod 644 /etc/somedir/ssl/certs/$HOSTNAME.pem
chmod 600 /etc/somedir/ssl/private_keys/$HOSTNAME.pem

hostname $HOSTNAME

# run puppetd once to set up puppet init scripts, etc.
#/usr/bin/somedird --test --server someserver.ph.liv.ac.uk
# or, set up puppet init scripts directly
cp /tmp/somedir/somedir.conf /etc/somedir/somedir.conf
echo "certname = $HOSTNAME" >> /etc/somedir/somedir.conf
echo "$HOSTNAME" > /etc/myhostname
cp /tmp/somedir/somedir-sysconfig /etc/sysconfig/somedir

# Put puppet on
#
#
/sbin/chkconfig puppet on  


# unmnt puppet install directory
umount /tmp/somedir
rmdir /tmp/somedir


# Format data RAID array with XFS and
# add new /data mnt point
# Kickstart creates array as swap,
# formatting with ext3 takes far too long

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
