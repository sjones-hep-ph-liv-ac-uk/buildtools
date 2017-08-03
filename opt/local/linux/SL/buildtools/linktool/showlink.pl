#!/usr/bin/perl
#---------------------------------------------
# Use this to convert ip or link
# 
#---------------------------------------------

use Getopt::Long;
use strict;

# Global options
my %parameter;

#-------------------------------------

# Read the options
initParams();

# Show the data

my $answer = '';

if (defined($parameter{'THEIP'})) { 
  $answer = sprintf("%02X%02X%02X%02X",split('\.',$parameter{'THEIP'}));
}
else {
  # C0A8010C
  my $x1 = hex(substr($parameter{'THELINK'},0,2));
  my $x2 = hex(substr($parameter{'THELINK'},2,2));
  my $x3 = hex(substr($parameter{'THELINK'},4,2));
  my $x4 = hex(substr($parameter{'THELINK'},6,2));

  $answer = "$x1.$x2.$x3.$x4";
}

print ("Conversion is $answer\n");

exit(0);

#---------------------------------------------
# Read the command line options
#---------------------------------------------
sub initParams() {

  # Read the options
  GetOptions ('h|help'      =>  \$parameter{'HELP'},
              'ip:s'        =>  \$parameter{'THEIP'} ,  
              'link:s'      =>  \$parameter{'THELINK'} ,  
	      );  

  if (defined($parameter{'HELP'})) {
    print <<TEXT;

Abstract: this can be used to convert an ip or a link.

  -h  --help                  Prints this help page
  -ip                ipaddr   Specifies the ip
  -link              link     Specifies the link
TEXT
    exit(0);
  }

  # Check that an IP or a link was defined.
  if (!(defined($parameter{'THEIP'}))) { 
    if (!(defined($parameter{'THELINK'}))) {
      die("You must give a link or an ip\n");
    }
  }
  if (defined($parameter{'THEIP'})) { 
    if ($parameter{'THEIP'} !~ /^\d+\.\d+\.\d+\.\d+$/) {
      die("Not a valid IP\n");
    }
  }
  if (defined($parameter{'THELINK'})) {
    if ($parameter{'THELINK'} !~ /^[0-9A-Fa-f]{8}$/) {
      die("Not a valid link\n");
    }
  }
}

#------- end -------
