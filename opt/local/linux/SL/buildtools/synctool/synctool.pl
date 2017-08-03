#!/usr/bin/perl
#---------------------------------------------
# Abstract: Use this to parse the hex link directory. 
# For every hex link that does not relate to hdBoot.cfg,
# insert the relevent section of a dhcpd.conf file. Sections 
# that relate to non-existing links, or which relate 
# to links that point to hdBoot.cfg, are omitted altogether.
#
# Mods:
#   03/12/08, sj, Put in an option to set the default gateway
#                 to the appropriate rack dependent address.
#   03/12/08, sj, next-server & subnet depend on run time IP.
#   19/12/08, sj, Put in a (slightly) kludgey fix to find if a
#                 desired link could not be made because not
#                 entry exists in dhcpdtab.cfg. It works OK,
#                 it's not the best way, but it is impossible
#                 to introduce a new bug this way.
#
#   26/01/09, sj, allow multiple hardware types
#   22/04/10, sj, suppressed leading zero in router address,
#                 using $bareRackNum.
#   
#---------------------------------------------

use Getopt::Long;
use strict;
use File::Temp qw/tempfile/;

# Options
my %parameter;

#-------------------------------------
# Ensure that no instance is already running
checkAndLock();

# Text of the default dhcpd wrapper. You can override this with an option.
my $wrapperText= <<EOT;
not authoritative;
deny unknown-clients;
allow booting;
allow bootp;
ddns-update-style ad-hoc;

option ip-forwarding    false;  # No IP forwarding
option mask-supplier    false;  # Don't respond to ICMP Mask req

subnet ST_SUBNET netmask 255.255.0.0 {
}

group {

 #Image server
 #next-server 192.168.99.123;
 #Test Image server
 next-server ST_NEXT_SERVER;

 #This is the pxe bootloader file
 filename "linux-install/pxelinux.0";

 #-------------------------------
 # SECTIONS GO HERE - DO NOT EDIT
 #-------------------------------

}
EOT

# Break up the text into an array
my @dhcpdWrapper;
foreach my $l (split(/\n/,$wrapperText )) {
  push (@dhcpdWrapper,$l . "\n");
}

# Get the local Ip and subnet
my $localSystemIp = getIpAddress();

$localSystemIp =~ /(\d+\.\d+)\.\d+\.\d+/;
my $classB = $1 ;

# Read the options 
initParams();

# Find where to put the host sections
my $insertPos = findInsertPos(@dhcpdWrapper) ;


# Find all links in the LINKDIR that do not point to a hdBoot.cfg
opendir(LINKDIR,$parameter{'LINKDIR'}) or die("Failed to open link dir\n");
my @allFiles = readdir(LINKDIR);
closedir(LINKDIR);

# Filter the files to hexlinks that do not point hdBoot.cfg
my %activeHexLinks = ();
foreach my $file (@allFiles) {
  if ($file =~ /^.*[0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F][0-9A-F]$/) {
    # it's a hexlink ...
    my $tgt = readlink($parameter{'LINKDIR'} . '/' . $file);
    if ($tgt!~ /^.*hdBoot.cfg/) {
      # ... pointing to a pxe/kickstart file, so mark it.
      $activeHexLinks{$file} = 1;
    }
  }
}

# Go over all the grid node IP addresses 
open(CONFIGFILE,$parameter{'CONFIGFILE'}) or die("Could not open $parameter{'CONFIGFILE'}\n");
while(<CONFIGFILE>) {

  # Break out the fields
  (my $mac,my $ip, my $ks ) = split(" ");
  
  # Make the hex link name for this IP address
  my $ipName = sprintf("%02X%02X%02X%02X",split('\.', $ip ));
  
  # See if the link exists
  if (-e $parameter{'LINKDIR'} . '/' . $ipName) {
    
    # See if it points to a kickstart boot file
    my $target = readlink($parameter{'LINKDIR'} . '/' . $ipName);
    if ($target !~ /^.*hdBoot.cfg/) {

      # Tick off that we have found a loaded hex link
      $activeHexLinks{$ipName} = 0;
            
      # We've got one. There should be an entry in the
      # dhcpd.conf file for this. The name shall be rXX-nXX.
      $ip =~ /\d+\.\d+\.(\d+)\.(\d+)/;
      my $rackNum = sprintf("%02d",$1);
      my $bareRackNum = sprintf("%d",$1);
      my $nodeNum = sprintf("%02d",$2);
      my $hostName = 'r' . $rackNum . '-n' . $nodeNum;
      
      # Get the default router (gateway address) for this system.
      # Compute it from (a) the first two fields of the IP address
      #                 (b) the rack number
      #                 (c) the gateway node, which defaults to 254.
      my $gateway = $classB . '.' . $bareRackNum . '.' . $parameter{'GATEWAYNODE'};

      # Put in the host section      
      splice(@dhcpdWrapper, $insertPos++, 0,"  \n"); 
      splice(@dhcpdWrapper, $insertPos++, 0,"  host $hostName {\n"); 
      splice(@dhcpdWrapper, $insertPos++, 0,"    hardware ethernet $mac;\n"); 
      splice(@dhcpdWrapper, $insertPos++, 0,"    fixed-address $ip;\n"); 
      splice(@dhcpdWrapper, $insertPos++, 0,"    option routers $gateway ;\n"); 
      splice(@dhcpdWrapper, $insertPos++, 0,"  }\n"); 
    }
  }
}
close(CONFIGFILE);

# Write out the new file


print("Overwriting existing output file\n") if (-e $parameter{'OUTPUTFILE'}) ;
open(OUTPUTFILE,">$parameter{'OUTPUTFILE'}") or die("Could not open output file, $parameter{'OUTPUTFILE'}");

foreach my $line (@dhcpdWrapper) {

  # Do next-server translation
  $line =~ s/ST_NEXT_SERVER/$localSystemIp/g;
  
  # Do subnet translation

  my $sn = $classB . '.0.0';
  $line =~ s/ST_SUBNET/$sn/g;
   
  print(OUTPUTFILE "$line");
}
close(OUTPUTFILE );

# Now report on any link that could not be determined
foreach my $link (keys(%activeHexLinks)) {
  if ($activeHexLinks{$link} != 0) {
    print("No dhcpd entry could be made for $link; check the dhcpdtab.cfg file.\n");
  }
}

#---------------------------------------------
# SUBROUTINES
#---------------------------------------------


#---------------------------------------------
# Read the command line options
#---------------------------------------------
sub initParams() {

  # Read the options
  GetOptions ('h|help'             =>   \$parameter{'HELP'},
              'd|linkdir:s'        =>   \$parameter{'LINKDIR'} ,   
              'w|dhcpdwrapper:s'   =>   \$parameter{'DHCPDWRAPPER'} ,   
              'c|config:s'         =>   \$parameter{'CONFIGFILE'} ,   
	      'o|outputfile:s'     =>   \$parameter{'OUTPUTFILE'} ,   
	      'gwn|gatewaynode:i'  =>   \$parameter{'GATEWAYNODE'} ,   
	      );

  if (defined($parameter{'HELP'})) {
    print <<TEXT;

Abstract: Use this to parse the hex link directory. 
For every hex link that relates to a pxe/kickstart file, 
insert the relevent section of a dhcpd.conf file. Sections 
that relate to non-existing links, or which relate 
to links that point to hdBoot.cfg, are omitted altogether.

 -h   --help                   Prints this help page
 -d   --linkdir        d       Dir where hex links live
 -w   --dhcpdwrapper   w       Alternative dhcpd.conf body 
 -c   --config         t       Table in "max_addr ip_addr ks=file" format
 -o   --outputfile     f       Output file, e.g. dhcpd.conf
 -gwn --gatewaynode    n       Optional value for gateway node (defs to 254)

TEXT
    exit(0);
  }
  
  # Validation and defaults
  
  if (!(defined( $parameter{'GATEWAYNODE'}))) {
    $parameter{'GATEWAYNODE'} = 254;
  }
  
  if (!(-d $parameter{'LINKDIR'})) {
    die("You must give a directory of ip file links\n");
  }
  
  if (!(-e $parameter{'CONFIGFILE'})) {
    die("You must give a table file that has the hostname, ethaddrs and ips\n");
  }
  
  if (!(defined($parameter{'OUTPUTFILE'}))) {
    die("You must give an output file\n");
  }
  
  if (defined($parameter{'DHCPDWRAPPER'})) {
    if (!(-e $parameter{'DHCPDWRAPPER'})) {
      die("The given wrapper file must exist\n");
    }

    # Blank the existing data    
    @dhcpdWrapper = ();
  
    # Read in the given dhcpd wrapper file
    open(DHCPDWRAPPER,$parameter{'DHCPDWRAPPER'}) or die("Could not open $parameter{'DHCPDWRAPPER'}\n");
    while(<DHCPDWRAPPER>) {
      my $line = $_;
      push(@dhcpdWrapper ,$line);
    }
    close(DHCPDWRAPPER);
  }
  
}

#---------------------------------------------
# Find the ip address for this system. If there is
# more than 1, count the 192.n.n.n addresses. If there
# are none or more than 1, fail, else return the single 
# 192 address.
#---------------------------------------------
sub getIpAddress() {

  # Run ifconfig
  my $ifconfig="/sbin/ifconfig";
  my @lines = qx|$ifconfig | or die("Can't get info from ifconfig: ".$!. "\n");
  
  my @addresses = ();
  my %oneNineTwos;
  
  # Go over the results
  foreach my $line (@lines){
    # Only choose lines with addresses, ignoring local
    if(($line =~ /inet addr:([\d.]+)/) && ($1 !~ /\s*127.*/)){
      my $addr = $1;
      push(@addresses,$addr );
      
      # Count the 192s.
      $oneNineTwos{$addr} = 1 if ($addr =~ /\s*192\..*$/);
    }
  }
  
  # Only 1 address
  return $addresses[0] if ($#addresses == 0);
  
  my @oneNineTwoKeys = keys(%oneNineTwos);

  # More than one address, but only one 192.n.n.n address
  return $oneNineTwoKeys[0] if ($#oneNineTwoKeys == 0);

  # More than one address, no single 192 address... game over
  die("Could not find a definitive ip address for this system\n");
}

#---------------------------------------------
# Find the position in the dhcpd wrapper where
# host sections should be inserted.
#---------------------------------------------
sub findInsertPos(@) {
  my @dhcpdWrapper = @_;
  
  my $lineCounter = 0;
  my $insertPos = 0;
  foreach my $line (@dhcpdWrapper) {
    $lineCounter++;
    if ($line =~ /SECTIONS GO HERE/) {
      $insertPos = $lineCounter;
    }
  }
  die ("Badly formed dhcpdwrapper - no sections marker\n") unless($insertPos > 0);
  return $insertPos ;
}

#---------------------------------------------
# Don't let the script run twice at once
#---------------------------------------------
sub checkAndLock() {
  die("Script is already running.\n") if (isAlreadyLocked());
  createLock();
}

#---------------------------------------------
# Create a type of lock file to show script is 
# running. It is automatically removed.
#---------------------------------------------
sub createLock() {
  my ($fh ,$name) = tempfile("/tmp/synctool.lck_XXXXX", UNLINK => 1);  
}

#---------------------------------------------
# Check if script is already running.
#---------------------------------------------
sub isAlreadyLocked() {
  opendir(DIR,"/tmp") or die("Could not open the lock dir (/tmp)\n");
  my @files=grep(/synctool.lck/, readdir(DIR));
  closedir(DIR);
  return 0 unless $#files > -1;
  return 1;
}

#------- end -------
