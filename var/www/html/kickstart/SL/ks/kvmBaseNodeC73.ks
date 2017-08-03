install
reboot
url --url="http://123.234.178.141/someshare/centos/7.3/os/x86_64/"
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

part /     --fstype xfs --size=15000  --asprimary
part swap                --size=4000
part /opt  --fstype xfs --size=15000
part /var  --fstype xfs --size=100 --grow

repo --name="CentoS_Seven" --baseurl=http://123.234.178.141/someshare/centos/7.3/os/x86_64/ --cost=100
repo --name="CentoS_Seven_updates" --baseurl=http://123.234.178.141/someshare/centos/7.3/updates/x86_64/ --cost=1000
repo --name="DependenciesEl7" --baseurl=http://123.234.178.142/someshare/someshare.puppetlabs.com/el/7/dependencies/x86_64/ --cost=101
repo --name="ProductsEl7" --baseurl=http://123.234.178.142/someshare/someshare.puppetlabs.com/el/7/products/x86_64/ --cost=100

services --enabled="chronyd"

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

%post --log=/root/ks-post.log

echo Starting post section
touch /root/deleteme

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
yum clean all
yum update

#--------------------------------------------------------------
# Add DPM someuser group and account to ensure consistent uid/gid
#
# 15.07.10 jb
#--------------------------------------------------------------
echo add someuser group 
#--------------------------------------------------------------
/usr/sbin/groupadd -g 104 someuser
/usr/sbin/useradd -c "DPM user" -d /home/someuser -g 104 -m -n -s /bin/bash -u 104 someuser

#---------------------------------------------
# Add a temporary host file.
#
# 29.01.09, sj
#---------------------------------------------
echo add a temporary host file  
#---------------------------------------------
# add a temporary hosts file
echo "# TEMP FILE ADDED BY KICKSTART                         " >  /etc/hosts
echo "127.0.0.1  localhost.localdomain localhost" >> /etc/hosts
echo ""                                                        >> /etc/hosts
echo "123.234.178.142 someserver.ph.liv.ac.uk"                >> /etc/hosts
echo "123.234.178.141 someserver.ph.liv.ac.uk"                       >> /etc/hosts
echo "123.234.48.110  vo10.ph.liv.ac.uk"                       >> /etc/hosts
echo "123.234.48.98   mike.ph.liv.ac.uk"                       >> /etc/hosts

#-----------------------------------------
# Set dns resolver
echo "search ph.liv.ac.uk" > /etc/resolv.conf
echo "nameserver 123.234.110.103" >> /etc/resolv.conf
echo "nameserver 123.234.110.104" >> /etc/resolv.conf

#---------------------------------------------
# Copying and installing various scripts, files and 
# crons. Also installs network parts, and some keys.
#
# 29.01.09, sj
#---------------------------------------------
echo installing various scripts  
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

#------------------------------------------------------------
# Eliminate 169.254.0.0 network
echo "NOZEROCONF=yes" >> /etc/sysconfig/network

#------------------------------------------------------------
# Set the hostname of the node
echo IFCONFIG OUTPUT
ifconfig
echo OUTPUT OF hostname
hostname
echo CONTENT OF /etc/hostname
cat  /etc/hostname

# RH6 .... HOSTNAME=`ifconfig|perl -lane 'if (/inet addr:(\d+)\.\d+\.\d+\.(\d+)/) { if($1!=127){$n=$2}}; END {print "hepgrid".($n % 100).".ph.liv.ac.uk"} '`
# RH7 :
HOSTNAME=`ifconfig|perl -lane 'if (/inet (\d+)\.\d+\.\d+\.(\d+)/) { if($1!=127){$n=$2}}; END {print "hepgrid".($n % 100).".ph.liv.ac.uk"} '`

echo Setting hostname to $HOSTNAME 
hostnamectl set-hostname $HOSTNAME
echo $HOSTNAME > /etc/hostname

echo IFCONFIG OUTPUT
ifconfig
echo OUTPUT OF hostname
hostname
echo CONTENT OF /etc/hostname
cat  /etc/hostname

#---------------
# Enable ssh in the firewall
/sbin/service firewalld restart
/usr/bin/firewall-cmd --permanent --add-service=ssh
/sbin/service firewalld restart

#---------------
if [ ! -e  /etc/someshare.repos.d/install_puppet.repo ]; then

  cat << EOF > /etc/someshare.repos.d/install_puppet.repo
[puppet_stuff1]
name=puppet_stuff1
baseurl=http://123.234.178.142/someshare/someshare.puppetlabs.com/el/7/dependencies/x86_64/ 
gpgcheck=0
enabled=1
[puppet_stuff2]
name=puppet_stuff2
baseurl=http://123.234.178.142/someshare/someshare.puppetlabs.com/el/7/products/x86_64/
gpgcheck=0
enabled=1
EOF

fi

yum -y install puppet

# Copy Puppet certs and enable on bootup
mkdir /tmp/somedir
mount -o nolock vo10.ph.liv.ac.uk:/data/somedir/mike /tmp/somedir/

MYHOSTNAME=`hostname`

mkdir -p /var/lib/somedir/ssl/certs
mkdir /var/lib/somedir/ssl/private_keys
chmod 771 /var/lib/somedir/ssl
chmod 755 /var/lib/somedir/ssl/certs
chmod 750 /var/lib/somedir/ssl/private_keys
/bin/cp -f /tmp/somedir/certs/ca.pem /var/lib/somedir/ssl/certs/

certlocation=/var/lib/somedir/ssl/certs/$MYHOSTNAME.pem
privkeylocation=/var/lib/somedir/ssl/private_keys/$MYHOSTNAME.pem

/bin/cp -f /tmp/somedir/certs/$MYHOSTNAME.pem $certlocation
/bin/cp -f /tmp/somedir/private_keys/$MYHOSTNAME.pem $privkeylocation

chmod 644 /var/lib/somedir/ssl/certs/$MYHOSTNAME.pem
chmod 600 /var/lib/somedir/ssl/private_keys/$MYHOSTNAME.pem

# Add initial puppet config so it uses mike as server
mkdir /etc/somedir
/bin/cp /tmp/somedir/somedir-mike.conf-centos7 /etc/somedir/somedir.conf

if [ -e $certlocation ]; then
  openssl x509 -noout -modulus -in $certlocation | openssl md5
fi
if [ -e $privkeylocation ]; then
  openssl rsa -noout -modulus -in  $privkeylocation | openssl md5
fi

umount /tmp/somedir
rmdir /tmp/somedir


#---------------------------------------------
# Set services.
# 29.01.09, sj
#---------------------------------------------
echo set services        
#---------------------------------------------
# switch services on/off
/sbin/chkconfig puppet on
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
/sbin/chkconfig firewalld on


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

echo end of post install  

%end

