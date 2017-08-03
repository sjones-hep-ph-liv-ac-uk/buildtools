#!/usr/bin/perl
#---------------------------------------------
# Abstract: A simple script to make a section of the dhcpd.conf file
# for the worker nodes in the grid.
# sj, 03/11/2008
# 
#---------------------------------------------

use Getopt::Long;
use strict;
use File::Temp qw/ :mktemp  /;

# Global options
my %parameter;
my @template;

#-------------------------------------

# Read the options
initParams();

# Open up the template file and read it in
open(TEMPLATE_FILE,$parameter{'TEMPLATE_FILE'}) or die("Failed to open template file\n");
while (<TEMPLATE_FILE>) {
  push(@template,$_);
}
close(TEMPLATE_FILE);

# Open up the file of H/W ethernet addresses, and thier rack and node numbers
open(ETHERNET_FILE,$parameter{'ETHERNET_FILE'}) or die("Failed to open ethernet file\n");
while (<ETHERNET_FILE>) {

  # Read in a ethernet line/record and parse the data out
  my $ethernetLine = $_;
  chomp($ethernetLine);
  $ethernetLine  =~ s/^\s*//;
  $ethernetLine  =~ s/\s*$//;
  die ("Poor format in ethernet file") unless(length($ethernetLine) > 0);
  my @etherParts = split(" ",$ethernetLine);
  my $ethAddr = $etherParts[0];
  my $rack = $etherParts[1];
  my $node = $etherParts[2];

  # Build up the data for the dhcpd.conf section for this node
  my $hostName = 'r' . $rack . "-" . 'n' . $node;
  my $ip = $parameter{'CLASS_B_STEM'} . "." . $rack . "." . $node;
 
  # Create a new section 
  my @section = ();
 
  # Go over the template, setting the data specific to this node 
  foreach my $templateLine (@template) {
  my $sectionLine = $templateLine ;
    $sectionLine =~ s/T_NODENAME/$hostName/;
    $sectionLine =~ s/T_FIXED_ADDRESS/$ip/;
    $sectionLine =~ s/T_MAC/$ethAddr/;
    $sectionLine =~ s/T_NEXT_SERVER/$parameter{'NEXT_SERVER'}/;
    $sectionLine =~ s/T_FILENAME/$parameter{'FILENAME'}/;
    push(@section ,$sectionLine);
  }

  # Print out the new section
  foreach my $sectionLine ( @section) {
    print($sectionLine);
  }
}
close(ETHERNET_FILE);

#---------------------------------------------
# SUBROUTINES
#---------------------------------------------




#---------------------------------------------
# Read the command line options
#---------------------------------------------
sub initParams() {

  # 

  # Read the options
  GetOptions ('h|help'            =>   \$parameter{'HELP'},
              'cbs|classbstem:s'  =>   \$parameter{'CLASS_B_STEM'},  
              'tf|templatefile:s'  =>  \$parameter{'TEMPLATE_FILE'},
              'ef|ethernetfile:s'  =>  \$parameter{'ETHERNET_FILE'},
              'ns|nextserver:s'  =>    \$parameter{'NEXT_SERVER'},
              'fn|filename:s'  =>      \$parameter{'FILENAME'},
	      );  

  if (defined($parameter{'HELP'})) {
    print <<TEXT;

Abstract: Abstract: A simple script to make a section of the dhcpd.conf file
for the worker nodes in the grid.

  -h   --help                  Prints this help page
  -cbs --classbstem            Class B Stem, e.g. 192.168
  -tf  --templatefile          File with a template in it
  -ef  --ethernetfile          File of ethernet and rack/node columns
  -ns  --nextserver            Next server (PXE)
  -fn  --filename              File name (PXE)
TEXT
    exit(0);
  }

  # Some validation
  if (!(defined($parameter{'CLASS_B_STEM'}))) {
    die("You must give a class B stem\n");
  }
  if (!(defined($parameter{'TEMPLATE_FILE'}))) {
    die("You must give a template file\n");
  }
  if (!( -e ($parameter{'TEMPLATE_FILE'}))) {
    die("You must give a template file that exists\n");
  }
  if (!(defined($parameter{'ETHERNET_FILE'}))) {
    die("You must give an ethernet file\n");
  }
  if (!( -e ($parameter{'ETHERNET_FILE'}))) {
    die("You must give an ethernet file that exists\n");
  }
  if (!(defined ($parameter{'NEXT_SERVER'}))) {
    die("You must give a next server value\n");
  }
  if (!( defined ($parameter{'FILENAME'}))) {
    die("You must give a filename\n");
  }
  
}


#------- end -------
