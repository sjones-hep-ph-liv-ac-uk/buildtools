#!/usr/bin/perl
#---------------------------------------------
# Use this to modify a dhcp.conf file, turning
# on and off ranges of hosts, or setting them to 
# various bootp servers.
#---------------------------------------------

use Getopt::Long;
use strict;
use File::Temp qw/ :mktemp  /;

# Hash of global options
my %parameter;

# Range of nodes and racks
my $MAXRACK = 23;
my $MAXNODE = 40;

# A means to tell if a given node has been specified.
my %rackNodeMap;

#-------------------------------------

# Read the options
initParams();

# Make a backup of the current dhcpd.conf file
my $backupFilename = backupFile($parameter{'DHCPDCONF'});

# Now read back that file into the original, changing it.
open(INPUTFILE,$backupFilename) or die ("Cannot open $backupFilename\n");
open(OUTPUTFILE,">$parameter{'DHCPDCONF'}") or die ("Cannot open $parameter{'DHCPDCONF'}\n");

# Go over all the lines
while(<INPUTFILE>) {
  my $lineIn = $_;
  chomp ($lineIn);

  if ($lineIn =~ /^\s*\#?\s*host\s+(\d+\-\d+)\s+.*$/) {
    # Found a host line
    my $rackNodeTag = $1;

    # It's the start of a host section. Get the rest of the host section.
    my @hostSectionLines = ();
    push(@hostSectionLines, $lineIn);
    while (<INPUTFILE> ) {
      my $hostLineIn = $_;
      chomp($hostLineIn);
      push(@hostSectionLines,$hostLineIn);

      # Look for the trailing curly bracket
      last if  ($_ =~ /^\s*\#?\s*\}\s*$/);
    }

    if (defined($rackNodeMap{$rackNodeTag})) {
      # This host in the list of desired ones (ones to change) 
      # The host is
      # a) in the list of desired nodes and
      # b) exists in the dhcpd.conf file. Mark it as "seen to".
      $rackNodeMap{$rackNodeTag} = 0;

      # Now make any necessary changes to it. 
      
      # First, maybe remove any existing NEXTSERVER or BOOTFILE entries
      if ($parameter{'REMOVE'} > 0 ) {
        @hostSectionLines = removeBootFileEntries(@hostSectionLines);
        @hostSectionLines = removeNextServerEntries(@hostSectionLines);
      }

      if (defined($parameter{'NEXTSERVER'})) {
        # There is a next-server clause to go in. 
        
        # Get rid of any existing next-server clause
        @hostSectionLines = removeNextServerEntries(@hostSectionLines);

        # Save the curly bracket.
        my $lastLine = pop(@hostSectionLines);

        # Put in the next-server clause, then restore the bracket        
        push(@hostSectionLines,"   next-server $parameter{'NEXTSERVER'}");
        push(@hostSectionLines,$lastLine);
      }

      # Is there any bootfile clause to go in? File strings are quoted.
      if (defined($parameter{'BOOTFILE'})) {
        # There is a "filename" clause to go in.

        # Get rid of any existing filename clause
        @hostSectionLines = removeBootFileEntries(@hostSectionLines);

        # Save the curly bracket.
        my $lastLine = pop(@hostSectionLines);

        # Put in the filename clause, then restore the bracket
        push(@hostSectionLines,"   filename   \"$parameter{'BOOTFILE'}\"");
        push(@hostSectionLines,$lastLine);
      }

      # Finally, is the whole string to be enabled/disabled?
      if ($parameter{'MODE'} eq 'disable') {
        @hostSectionLines = disableHostSection(@hostSectionLines);
      }

      if ($parameter{'MODE'} eq 'enable') {
        @hostSectionLines = enableHostSection(@hostSectionLines);
      }
    }

    # Write the host section out
    foreach my $opLine (@hostSectionLines) {
      print(OUTPUTFILE $opLine,"\n");
    }
  }
  else {
    # It's no host section. Just print the line out.
    print(OUTPUTFILE $lineIn,"\n");
  }
}

close(INPUTFILE);
close(OUTPUTFILE);

# Check for any nodes that were specified, but didn't get found
foreach my $nodeKey (sort mySort keys %rackNodeMap) {
  if ($rackNodeMap{$nodeKey} == 1) {
    print("Node $nodeKey was specified but not found in $parameter{'DHCPDCONF'}\n");
  }
}

#---------------------------------------------
# SUBROUTINES
#---------------------------------------------

#---------------------------------------------
# Enable a host section
#---------------------------------------------
sub enableHostSection (@) {
  my @returnValue = ();
  foreach my $line (@_) {
    # Get rid of leading hash symbols
    $line =~ s/^\s*\#//;
    push(@returnValue,$line);
  }
  return @returnValue;
}

#---------------------------------------------
# Disable a host section
#---------------------------------------------
sub disableHostSection (@) {
  my @returnValue = ();
  foreach my $line (@_) {
    if ($line !~ /^\s*\#/) {
    # Insert leading hash symbols
      $line =~ s/^/#/;
    }
    push(@returnValue,$line);
  }
  return @returnValue;
}
#---------------------------------------------
# Remove existing boot file entry
#---------------------------------------------
sub removeBootFileEntries(@) {
  my @returnValue = ();
  foreach my $line (@_) {
    # If the line matches a filename (boot file) entry, get rid of it
    if ($line !~ /^\s*\#?\s*filename\s+.*$/) {
      push(@returnValue,$line);
    }
  }
  return @returnValue;
}

#---------------------------------------------
# Remove existing next server entry
#---------------------------------------------
sub removeNextServerEntries(@){
  my @returnValue = ();
  foreach my $line (@_) {
    # If the line matches a next-server entry, get rid of it
    if ($line !~ /^\s*\#?\s*next\-server\s+.*$/) {
      push(@returnValue,$line);
    }
  }
  return @returnValue;
}

#---------------------------------------------
# A sort routine to sort rack/node keys, like 1-38 etc.
#---------------------------------------------
sub mySort() {

  # Break up key A
  $a =~ /(\d+)\-(\d+)/;
  my $ap1 = $1; my $ap2 = $2;

  # Break up key B
  $b =~ /(\d+)\-(\d+)/;
  my $bp1 = $1; my $bp2 = $2;

  # Key comparisons.

  # Compare the first parts
  return  1 if ($ap1 > $bp1);
  return -1 if ($ap1 < $bp1);

  # Hm... the first parts must have been equal. So
  # it depends on the 2nd parts
  return  1 if ($ap2 > $bp2);
  return -1 if ($ap2 < $bp2);

  # Hm... the 2nd parts were equal too. Whole thing is equal.
  return 0;
}

#---------------------------------------------
# Use this to backup the input dhcpd.conf file
#---------------------------------------------
sub backupFile($) {

  my $theFileToBackup = $_[0];

  # Get an open temp file for the backup
  my ($backupHandle, $backupFile) = mkstemp( "dhcpd.conf.bkp_XXXXX" );
 
  # Peddle through the input file, backup up the lines 
  open(INPUTFILE,$theFileToBackup) or die ("Cannot open $theFileToBackup\n");
  while(<INPUTFILE>) {
    print ($backupHandle $_);
  }
  close(INPUTFILE);
  close($backupHandle);
  
  # Check the backup worked OK
  my $dhcpdSize = -s $theFileToBackup;
  my $backupSize = -s $backupFile;
  if ($dhcpdSize != $backupSize) {
    die ("Quiting; couldn't backup the dhcpd.conf file, $dhcpdSize, $backupSize \n");
  }
  return $backupFile;
}

#---------------------------------------------
# Use this to parse a range of racks or nodes.
#---------------------------------------------
sub parseRange($) {

  # A list of things specified in the range
  my @theList;

  my $theRange = $_[0];

  if ($theRange =~ /(\d+)\-(\d+)/) {
    # It's a 1-4 sort of thing, so get the values at the ends, e.g 1 and 4
    my $lower = $1;
    my $upper = $2;

    # Makes sense?
    if ($lower > $upper) {
      die ("Node spec $parameter{'NODESPECS'} has poorly defined range, $lower to $upper\n");
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
        my @bits = split(",",$theRange);

        # Get the elements out and put them in the list
        foreach my $bit (@bits) {
          push(@theList,$bit);
        }
      
      }
      else {
        # It's not right.
        die ("Node spec $parameter{'NODESPECS'} is poorly defined\n");
      }
    }
  }

  return @theList;
}


sub initParams() {

  # Can accept an array of node specs
  $parameter{'NODESPECS'} = [];

  # Read the options
  GetOptions ('h|help'           =>   \$parameter{'HELP'},
              'n|nodespecs:s'    =>    $parameter{'NODESPECS'} ,  
              'm|mode:s'         =>   \$parameter{'MODE'} ,   
              'ns|next-server:s' =>   \$parameter{'NEXTSERVER'} ,   
              'bf|bootfile:s'    =>   \$parameter{'BOOTFILE'} ,   
	      'r|remove:i'       =>   \$parameter{'REMOVE'} ,
              'd|dhcpd:s'        =>   \$parameter{'DHCPDCONF'} );

  if (defined($parameter{'HELP'})) {
    print <<TEXT;

Abstract: this can be used to enable/disable dhcpd entries for a given set of hosts,
and to insert or remove next-server and filename lines for each host section.

  -h  --help                  Prints this help page
  -n  --nodespecs    1/2      Specifies a rack/node. Can use lists, ranges and asterixes
  -m  --mode         enable   Should be enable or disable (takes the host section out)
  -ns --next-server  192...   Inserts a next-server line in each host section
  -bf --bootfile     file     Inserts a filename line in each host section
  -r  --remove       0/1      Removes next-server and filename lines from host sections
  -d  --dhcpd        file     Specfies the file to work on

TEXT
    exit(0);

  }

  # All racks or nodes may be specified

  foreach my $n (@{$parameter{'NODESPECS'}}) {

    my @racks;
    my @nodes;

    # Basic validation, e.g. racks/nodes
    if ($n !~ /^(.+)\/(.+)$/) {
      die ("Node spec $n not well formed\n");
    }

    # Get the part of the nodespec that specifies the racks
    my $rackBit = $1;
  
    # Get the part of the nodespec that specifies the nodes
    my $nodeBit = $2;
    
    # Find out about the nodes and racks
    
    if ($rackBit eq '*') {  
      # There's a star in the "racks" field. That means "all racks"
      @racks = ( 1 .. $MAXRACK);
    }
    else {
      # Not a star. It could be 1 or 1,4, or 10-15. Pass it to a routine to
      # break it up and get the array of racks
      @racks = parseRange($rackBit );
    }
    
    if ($nodeBit eq '*') {
      # There's a star in the "nodes" field. That means "all nodes" in the
      # specified racks
      @nodes = ( 1 .. $MAXNODE);
    }
    else {
      # Not a star. It could be 1 or 1,4, or 10-15. Pass it to a routine to
      # break it up and get the array of nodes
      @nodes = parseRange($nodeBit  );
    }

    # Now set the fields in the rack/node map to note what nodes to process.
    foreach my $r (@racks) {
      foreach my $n (@nodes) {
        my $rackNodeKey = $r . "-" . $n;
        $rackNodeMap{$rackNodeKey} = 1;
      }
    }
  }

  # Basic validation of the mode
  if (defined($parameter{'MODE'})) {
    if (($parameter{'MODE'} ne  "enable") and
        ($parameter{'MODE'} ne  "disable")) {
      die ("Mode must be enable or disable\n");
    }
  }
  else {
    $parameter{'MODE'} = "nochange"
  }

  # Is the file there? Can we open it to read it?
  if (!defined($parameter{'DHCPDCONF'})) {
    die ("You must specify a file\n");
  }
  if ( ! ( -r $parameter{'DHCPDCONF'})) {
    die ("You must specify a file that exists and can be read\n");
  }
  
  # Give default to remove. By default, do not remove.
  if (!defined($parameter{'REMOVE'})) {
    $parameter{'REMOVE'} = 0;
  }
}
#------- end -------

