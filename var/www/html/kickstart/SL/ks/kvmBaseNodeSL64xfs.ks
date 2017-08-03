# Kickstart file automatically generated by anaconda.

#version=DEVEL
reboot
install
url --url=http://someserver.ph.liv.ac.uk/someshare/linux/scientific/6.4/x86_64/os/
lang en_US.UTF-8
keyboard uk
#text
skipx

#%include /tmp/network.ks

rootpw  --iscrypted ABC
firewall --disabled
authconfig --enableshadow --passalgo=sha512
selinux --disabled
timezone --utc Europe/London
bootloader --location=mbr --driveorder=sda --append="rhgb quiet"
#Partitioning manual for fear of trashing RAIDs

# Disk partition
# Manual for fear of trashing RAID arrays

# Disk partition
zerombr yes
clearpart --all

part /     --fstype ext3 --size=12000  --asprimary
part swap                --size=4000
part /opt  --fstype xfs --size=12000
part /var  --fstype xfs --size=100 --grow

repo --name="Scientific LinuX"  --baseurl=http://someserver.ph.liv.ac.uk/someshare/linux/scientific/6.4/x86_64/os/ --cost=100
repo --name="Scientific LinuX Updates"  --baseurl=http://someserver.ph.liv.ac.uk/someshare/linux/scientific/6.4/x86_64/updates/security/ --cost=1000

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
-dovecot
-spamassassin
-yum-autoupdate
-systemtap-runtime

%post

(

#--------------------------------------------------------------
# Get rid of some odd repos
#
# 13.02.14 sj
#--------------------------------------------------------------
rm /etc/someshare.repos.d/sl6x.repo  
rm /etc/someshare.repos.d/sl-other.repo  
rm /etc/someshare.repos.d/sl.repo
yum clean all

#--------------------------------------------------------------
# Add DPM someuser group and account to ensure consistent uid/gid
#
# 15.07.10 jb
#--------------------------------------------------------------
/usr/sbin/groupadd -g 104 someuser
/usr/sbin/useradd -c "DPM user" -d /home/someuser -g 104 -m -n -s /bin/bash -u 104 someuser

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
echo "123.234.178.141 someserver.ph.liv.ac.uk"                       >> /etc/hosts
echo ""

#---------------------------------------------
# A kickstart component to set services.
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

# Install the cron entries
echo "# Kickstart " > /var/spool/cron/root
echo "# Puppet Name: restart_puppet"                       >> /var/spool/cron/root
echo "*/30 * * * * /root/bin/restart_puppet.sh"            >> /var/spool/cron/root
chmod 600 /var/spool/cron/root

# Install the files
mkdir /root/bin
mkdir /root/scripts
chmod 755 /root/bin
chmod 755 /root/scripts
cp /tmp/scripts/restart_puppet.sh /root/bin/restart_puppet.sh
chmod 755 /root/bin/restart_puppet.sh

# unmnt scripts scripts/files directory
umount /tmp/scripts
rmdir  /tmp/scripts

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

#rpm -ivh /tmp/somedir/facter-1.5.2-1.x86_64.rpm /tmp/somedir/somedir-0.24.6-1.x86_64.rpm
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

# Activate puppet service on boot
#
/sbin/chkconfig puppet on  

# unmnt puppet install directory
umount /tmp/somedir
rmdir /tmp/somedir

yum clean all

sleep 30

echo end of post install      >> /tmp/kslog.txt

)

%end