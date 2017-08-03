install
reboot
url --url=http://someserver.ph.liv.ac.uk/someshare/centos/7.1.1503/os/x86_64/
lang en_GB.UTF-8
keyboard uk

skipx
text

rootpw  --iscrypted ABC
firewall --disabled
authconfig --enableshadow --passalgo=sha512
selinux --disabled
timezone --utc Europe/London
bootloader --location=mbr --driveorder=sda --append="rhgb quiet"

# Disk partition
zerombr 
clearpart --all

part /     --fstype ext3 --size=10000  --asprimary
part swap                --size=3000
part /opt  --fstype ext3 --size=10000
part /var  --fstype ext3 --size=100 --grow

repo --name="CentoS_Seven"  --baseurl=http://someserver.ph.liv.ac.uk/someshare/centos/7.1.1503/os/x86_64/       --cost=100
repo --name="CentoS_Seven_updates"  --baseurl=http://someserver.ph.liv.ac.uk/someshare/centos/7.1.1503/updates/x86_64/  --cost=1000

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
-dovecot
-spamassassin
-yum-autoupdate
-systemtap-runtime

%end

%post

(

#--------------------------------------------------------------
# Get rid of some odd repos and modify the others to suit setup here
#
# 04.01.16 sj
#--------------------------------------------------------------
yum clean all
#rm -f /etc/someshare.repos.d/CentOS-Debuginfo.repo
#rm -f /etc/someshare.repos.d/CentOS-fasttrack.repo
#rm -f /etc/someshare.repos.d/CentOS-Sources.repo
#rm -f /etc/someshare.repos.d/CentOS-Vault.repo
cd /etc/someshare.repos.d
sed -i \
   -e "s/^mirrorlist/#mirrorlist/" \
   -e "s/\#baseurl/baseurl/" \
   -e "s/http:\/\/mirror.centos.org\/centos\/\$releasever/http:\/\/someserver.ph.liv.ac.uk\/someshare\/centos\/7.1.1503/" \
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
echo ""

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

# unmnt scripts scripts/files directory
umount /tmp/scripts
rmdir  /tmp/scripts


#--------------------------------------------------------------
# Add puppet
#
# 04.01.16 sj
#--------------------------------------------------------------
cat > /etc/someshare.repos.d/epel7.repo <<END_OF_EPEL7_REPO
[epel7]
name=epel7
baseurl=http://someserver.ph.liv.ac.uk/someshare/pub/epel/7/x86_64
enabled=1
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
END_OF_EPEL7_REPO
###
yum install -y --nogpgcheck ruby-augeas
yum install -y --nogpgcheck facter
yum install -y --nogpgcheck rubygem-rgen
yum install -y --nogpgcheck hiera
yum install -y --nogpgcheck ruby-shadow
yum install -y --nogpgcheck puppet

echo "# Kickstart " > /var/spool/cron/root
echo "# Puppet Name: restart_puppet"                       >> /var/spool/cron/root
echo "*/30 * * * * /root/bin/restart_puppet.sh"            >> /var/spool/cron/root
chmod 600 /var/spool/cron/root

mkdir /tmp/somedir
mount -o nolock someserver.ph.liv.ac.uk:/data/somedir/client /tmp/somedir/

mkdir /root/bin
chmod 755 /root/bin
cp /tmp/somedir/somedir3/restart_puppet.sh /root/bin/restart_puppet.sh
chmod 755 /root/bin/restart_puppet.sh

HOSTNAME=`hostname`

# pre-generated puppet certificate
mkdir -p /var/lib/somedir/ssl/certs
mkdir /var/lib/somedir/ssl/private_keys
chmod 771 /var/lib/somedir/ssl
chmod 755 /var/lib/somedir/ssl/certs
chmod 750 /var/lib/somedir/ssl/private_keys
cp /tmp/somedir/certs/ca.pem /var/lib/somedir/ssl/certs/
cp /tmp/somedir/certs/$HOSTNAME.pem /var/lib/somedir/ssl/certs/
cp /tmp/somedir/private_keys/$HOSTNAME.pem /var/lib/somedir/ssl/private_keys/
chmod 644 /var/lib/somedir/ssl/certs/$HOSTNAME.pem
chmod 600 /var/lib/somedir/ssl/private_keys/$HOSTNAME.pem

cp /tmp/somedir/somedir3/somedir.conf /etc/somedir/somedir.conf
sed -i -e 's/pluginsync = .*/pluginsync = false/' -e 's/report = .*/report = false/' /etc/somedir/somedir.conf
umount /tmp/somedir
rmdir /tmp/somedir

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

yum clean all

sleep 3

echo end of post install      >> /tmp/kslog.txt

)

%end
