#!/usr/bin/perl

my $hostName;
my $macAddr;
my $ipAddr;
while(<>) {
  if ($_ =~ /host\s*(\S+)\s*/) {
    $hostName = $1;
  }
  if ($_ =~ /hardware ethernet\s*(\S+)\s*/) {
    $macAddr  = $1;
  }
  if ($_ =~ /fixed-address\s*(\S+)\s*/) {
    $ipAddr   = $1;
    $line = $hostName . "\t" . $macAddr . "\t" . $ipAddr . "\n";
    $line =~ s/\;//g;
    print $line;
  }
}
