#!/usr/bin/perl

use strict;
use warnings;

use Data::Dumper;

sub read_settings( $$ );

my %settings;

unless (@ARGV == 3)
{
  print "Usage: $0 source_file destination_file variable_name\n";
}

my ($source, $destination, $name) = @ARGV;


unless (-r $source)
{
  die "Can't open source file $source: $!";
}

%settings = ();

read_settings( $source, \%settings );

open OUT, '>', $destination or die "Can't open destination file $destination: $!";

print OUT Data::Dumper->Dump( [\%settings], [$name] );

close OUT;

exit 0;


#------------------------------------------------------------------------------
# sub read_settings( file, hash )
#
# Reads the hash from the named file.  Handles a hash of hashes.
#------------------------------------------------------------------------------

sub read_settings( $$ )
{
  my ($file, $hash) = @_;

  my $item= '';

  open IN, '<', $file or die "Can't open $file for input: $!";

  foreach my $line (<IN>)
  {
    chomp $line;

    next unless ($line);

    if ($line =~ m/^\[(.*)\]$/)
    {
      $item = $1;
    }
    else
    {
      my ($field, $value) = split /\s*=\s*/, $line, 2;

      $$hash{$item}{$field} = $value;
    }
  }

  close IN;
}
