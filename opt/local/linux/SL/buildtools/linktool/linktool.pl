#!/usr/bin/perl
#---------------------------------------------
# Use this to create a set of links. The links
# are from HexIp-named links to some other file.
# 
# Notes:
#
# pxelinux.0 searches for a config file that
# it can use. To do this search, it starts in the directory
# from where pxelinux.0 was downloaded. To do it, it also 
# adds the path "pxelinux.cfg/". In there it searches for files. It 
# has an algorithm to find the files. It takes
# its IP, converts it to a HEX value and searches for it. 
# Example: 192.168.50.01 is C0A83201, when viewed in HEX.
#
# So it searches for C0A83201. If it finds it, fine, it uses
# it. If not, it takes one digit off, and tries C0A8320. This
# goes on until it either finds a match, or fails. If it fails,
# it tries "default". If it fails then, that's the end of it.
#
# We use links to link to the ACTUAL config. There are
# planned to be several actual config files, and each system
# that can be rebuilt has a HexIp-named link to one of those files.
#
# The first file (say hdBoot.cfg) tells pxelinux.0 to boot from
# its hard drive. So it doesn't rebuild.
#
# Other files (say default.ks.cfg) tell pxelinux.0 to boot
# from a "kickstart kernel" that will be delivered via NFS across 
# the network, and rebuild the box using it. Each hardware type has 
# its own type of file.
#
# So, whether the box rebuilds or not depends on where its link
# points. 
#
# We could set up all those links by hand, which would
# work, but there are 500 or more. So I've written this script
# that will allow you to make all the required links instantly.
#
# That's what this tool does. To use it, give it a file name
# and a IP range or a full address. It will make all the links
# from each of the IPs specfied to the file you give.
#
# Hopefully, that will make things easier. If you give in a
# smaller IP, say a class B, e.g. 192.168, it will add each
# subnet as well, in turn. That makes a lot of links, but
# allows you to build the whole farm.
#
# It also occured to me that we may need to filter
# the output based on a range of racks and/or nodes.
# Therefore, I've added filters, so that you
# can say "-r 1-4 -n 3-7". That will write links for
# racks 1-4 and nodes 3-7 in each of those racks. 
# This assumes that the rack number is synonymous with
# the third byte of the IP, and the node number is 
# synonymous with with the last byte of the IP.
# You can also use 1,2,4 (i.e. to miss rack or nodes).
# 
# I think this will be the best way to use the tool,
# i.e. -ip 192.168 -r 1-4 -n 1-4
# That would reboot/build racks 1 to 4, but only nodes 1-4
# within those racks.
#
# 26/01/09, sj, multiple hardware types
#               I've added a config file, that holds a table. The
#               last column of the table has a filename for that
#               hardware type. This is used to make a hardware
#               specific kickstart configuration.
# 
#---------------------------------------------

use Getopt::Long;
use strict;
use File::Temp qw/ :mktemp  /;
use File::Basename;

# Global options
my %parameter;

#-------------------------------------

# Read the options
initParams();

# Structure to hold all the nodes, deduplicated and filtered.
my %allIpNodes;

# To filter by specific nodes: This array will have a
# list of the last parts of the dotted quad, i.e.
# 1.2.3.(4), 4 in that case. The links will be restricted
# to that value.
my @nodes;

# To filter by specific racks. This array will have a
# list of the third part of the dotted quad, i.e.
# 1.2.(3).4, 3 in that case. The links will be restricted
# to that value.
my @racks;
# Go over all the ip ranges
foreach my $ip (@{$parameter{'IPRANGE'}}) {

  # Basic validation
  die ("Illegal ip -- $ip\n") if ($ip !~ m/^(\d+\.?)+$/) ;

  # Get rid of any trailing dot (it's legal, but unwanted)
  $ip =~ s/\.$//;
  
  # Break the ip up
  my @parts = split('\.',$ip);

  # More validation  
  my $partCount = $#parts + 1;
  die ("Illegal ip -- $ip\n") if (($partCount > 4) or ($partCount < 1)) ;

  # Push the first ip range onto the stack
  my @ipNodes = ();
  push(@ipNodes,$ip);
 
  # Find if it is a full ip spec, or a network range 
  my $classesToAdd = 4 - $partCount;
  for (my $ii = 0; $ii < $classesToAdd; $ii++) {
    # For ranges, add classes to the required depth
    @ipNodes = addClass(@ipNodes);
  }

  # Apply filters and remove duplicates
  foreach my $n (@ipNodes) {
    if (passesFilters($n)) {
      $allIpNodes{$n} = 1;
    }
  }
  
}

# Now make the links
my $countLinks = 0;
foreach my $n (keys(%allIpNodes)) {
  # Convert each IP address into a HexIp-named link
  my $hexIpName = sprintf("%02X%02X%02X%02X",split('\.',$n));

  # Prepare to make a link. First, get the KICKSTART filename
  # for this node.
  my $kickStartClause = getKickStartClause($parameter{'CONFFILE'},$n);

  # Now get the kernel (stuff efficiency)
  my $kickStartKernelDir =  getKickStartKernel($parameter{'CONFFILE'},$n);

  # Now make a real boot file for this node
  my $realBootFile = makeRealBootFile($kickStartClause,$kickStartKernelDir,$parameter{'BOOTFILETEMPLATE'});

  # Make the link
  system("ln -sf $realBootFile $hexIpName");
  $countLinks++;
}

if ($countLinks == 0) {
  print("The inputs you affected no links. ");
  print("Please check ip, racks and nodes.\n");
}

#---------------------------------------------
# SUBROUTINES
#---------------------------------------------
#---------------------------------------------
# Parse the config file to find the boot file for this hardware
#---------------------------------------------
sub getKickStartClause($$) {
  # TODO cache and optimise
  my $ipToFind = $_[1];
  open(CONFFILE,"$parameter{'CONFFILE'}") or die ("Unable to open the config file\n");
  while (<CONFFILE>) {
    next unless ($_ !~ "^\s*#");   # Allow comments
    my @fields = split(" ",$_);
    die ("Poor structure in config file\n") unless $#fields == 3;
    my $recordIp = $fields[1];
    if ($recordIp eq $ipToFind) {
      close(CONFFILE);
      return $fields[2];
    }
  }
  close(CONFFILE);
  die("Unable to find a hardware specific kickstart clause. Check the config file for $ipToFind\n");
}

#---------------------------------------------
# Parse the config file to find the kernel for this hardware
#---------------------------------------------
sub getKickStartKernel($$) {
  # TODO cache and optimise
  my $ipToFind = $_[1];
  open(CONFFILE,"$parameter{'CONFFILE'}") or die ("Unable to open the config file\n");
  while (<CONFFILE>) {
    next unless ($_ !~ "^\s*#");   # Allow comments
    my @fields = split(" ",$_);
    die ("Poor structure in config file\n") unless $#fields == 3;
    my $recordIp = $fields[1];
    if ($recordIp eq $ipToFind) {
      close(CONFFILE);
      return $fields[3];
    }
  }
  close(CONFFILE);
  die("Unable to find a hardware specific kickstart kernel. Check the config file for $ipToFind\n");
}


#---------------------------------------------
# Parse the config file to find the boot file for this hardware
#---------------------------------------------
sub makeRealBootFile($$) {

  my $kickStartClause = $_[0];
  my $kickStartKernelDir = $_[1];
  my $bootFileTemplate = $_[2];

  # Get the directory to make the new file in, which is the same dir as the
  # template.
  my $absPath = File::Spec->rel2abs($bootFileTemplate);
  my $dirname = dirname($absPath);

  # Make the name of the new file

  my @allParts = split('/' ,$kickStartClause);
  my $lastPart = $allParts[$#allParts];

  my $pxeFile  = $lastPart . '_' . $parameter{'BADBLOCK'} . '.cfg';

  # Go over the lines in the template, making the new file, and translating in the
  # name of the actual boot file and kernel for this hardware type.
  open(BOOTFILETEMPLATE,"$parameter{'BOOTFILETEMPLATE'}") or die ("Unable to open the boot file template\n");
  open(NEWBOOTFILE,">$pxeFile") or die("Unable to open the new boot file $pxeFile\n");
  while (<BOOTFILETEMPLATE>) {
    $_ =~ s/LT_BADBLOCK/badblock=$parameter{'BADBLOCK'}/;
    $_ =~ s/LT_KSFILE/$kickStartClause/;
    $_ =~ s/LT_KSKERNELDIR/$kickStartKernelDir/;
    print(NEWBOOTFILE $_);
  }
  close(BOOTFILETEMPLATE);
  close(NEWBOOTFILE);
  return $pxeFile ;
}



#---------------------------------------------
# Apply node/rack filters
#---------------------------------------------
sub passesFilters(){
  my $ip = $_[0];

  my $nodeOk ;
  my $rackOk ;
    
  # Apply node filter first
  if ($#nodes < 0) {
    # No allowed nodes defined, so any node is OK
    $nodeOk = 1;
  }
  else {
    # Allowed nodes were defined. Id this node value.
    $ip =~ m/^\d+\.\d+\.\d+\.(\d+)$/;
    my $nodeValue = $1;
    # If the nodeValue doesn't exist in any filter, it fails.
    $nodeOk = 0;
    foreach my $allowedNode(@nodes) {
      if ($nodeValue ==$allowedNode) {
        $nodeOk = 1;
      }
    }
  }
  
  # Right. We've tested the nodes. Bomb out early if the node is
  # not OK (no point doing more).
  return 0 unless $nodeOk;
  
  # Apply rack filter second
  if ($#racks < 0) {
    # No allowed racks defined, so any rack is OK
    $rackOk = 1;
  }
  else {
    # Allowed racks were defined. Id this rack value.
    $ip =~ m/^\d+\.\d+\.(\d+)\.\d+$/;
    my $rackValue = $1;
    # If the rackValue doesn't exist in any filter, it fails.
    $rackOk = 0;
    foreach my $allowedRack(@racks) {
      if ($rackValue == $allowedRack) {
        $rackOk = 1;
      }
    }
  }
  # Right. We've tested the racks. Bomb out if the rack is
  # not OK .
  return 0 unless $rackOk;
  
  return 1;

}

#---------------------------------------------
# Expand an IP to have a new subnet/class
#---------------------------------------------
sub addClass(){
  my @oldNodes = @_;
  my @newNodes = ();

  foreach my $oldNode(@oldNodes) {
  
    # Add lines for subnets 1 to 254 (miss out 0 and 255, as
    # they are special.
    for (my $ii = 1; $ii <= 254  ; $ii++) {
      my $madeUpNode = $oldNode . "." . $ii;
      push(@newNodes,$madeUpNode);
    }
  }
  return @newNodes;
}



#---------------------------------------------
# Read the command line options
#---------------------------------------------
sub initParams() {

  # Can accept an array of ip specs
  $parameter{'IPRANGE'} = [];

  # Read the options
  GetOptions ('h|help'            =>   \$parameter{'HELP'},
              'ip|iprange:s'      =>    $parameter{'IPRANGE'} ,  
              'n|nodes:s'         =>   \$parameter{'NODES'} ,  
              'c|conf:s'          =>   \$parameter{'CONFFILE'} ,  
              'r|racks:s'         =>   \$parameter{'RACKS'} ,  
              't|template:s'      =>   \$parameter{'BOOTFILETEMPLATE'} ,
              'b|badblock:i'      =>   \$parameter{'BADBLOCK'} ,
	      );  

  if (defined($parameter{'HELP'})) {
    print <<TEXT;

Abstract: this can be used to enable/disable rebuilding. See the text at the top of the
script for more information. 

  -h  --help                  Prints this help page
  -ip --iprange      ipaddr   Specifies the range of ips
  -t  --template     file     The bootfile template to use
  -r  --racks        spec     List or range of specific racks (right byte - 1 of IP)
  -n  --nodes        spec     List or range of specific nodes (right byte of IP)
  -c  --conf         file     Config file
  -b  --badblock     0/1      Run badblock
TEXT
    exit(0);
  }


  # Check that some rack/nodes were specfied
  if (@{$parameter{'IPRANGE'}} <= 0) {
    die("You didn't specify an ip range\n");
  }
  
  # Check existing bootfile was given
  if (!(defined($parameter{'BOOTFILETEMPLATE'}))) {
    die("You must give a boot file\n");
  }

  if ( ! -f $parameter{'BOOTFILETEMPLATE'}) {
    die("You must give a boot file that exists\n");
  }

  # Check existing config file was given
  if (!(defined($parameter{'CONFFILE'}))) {
    die("You must give a config file\n");
  }

  if ( ! -f $parameter{'CONFFILE'}) {
    die("You must give a config file that exists\n");
  }

  if (!(defined($parameter{'BADBLOCK'}))) {
    $parameter{'BADBLOCK'} = 0;
  }
  
  # Check if we are to filter on node number
  if (!(defined($parameter{'NODES'}))) {
    # None means there is no restriction
    @nodes = ();
  }
  else {
    # Interpret the range (1,2,4 .. or 1-4 etc)
    @nodes = parseRange($parameter{'NODES'});
  }
  
  # Check if we are to filter on rack number
  if (!(defined($parameter{'RACKS'}))) {
    # None means there is no restriction
    @racks = ();
  }
  else {
    # Interpret the range (1,2,4 .. or 1-4 etc)
    @racks = parseRange($parameter{'RACKS'});
  }
  
}

#---------------------------------------------
# Use this to parse a range of nodes or racks
#---------------------------------------------
sub parseRange($) {

  # A list of things specified in the range
  my @theList = ();

  my $theRange = $_[0];

  if ($theRange =~ /(\d+)\-(\d+)/) {
    # It's a 1-4 sort of thing, so get the values at the ends, e.g 1 and 4
    my $lower = $1;
    my $upper = $2;

    # Makes sense?
    if ($lower > $upper) {
      die ("Spec $theRange has poorly defined range, $lower to $upper\n");
    }

    # Generate all the values between (inc.)
    for (my $ii = $lower;$ii <= $upper;$ii++) {
      push(@theList,$ii);
    }
  }
  else {
    if ($theRange =~ /^(\d+)$/) {
      # It's just a simple (one element) value. Push it one the list.
      push(@theList,$1);
    }
    else {
      if ($theRange =~ /^((\d+\,?)+)$/) {
        # It's a comma separated list. Break it up on commas.
        @theList= split(",",$theRange);
      }
      else {
        # It's not right.
        die ("Spec $theRange is poorly defined\n");
      }
    }
  }
  return @theList;
}

#------- end -------
