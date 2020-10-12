#!/usr/bin/perl

############################################################################
#                                                                          #
# Send log and status emails for IPFire                                    #
#                                                                          #
# This is free software; you can redistribute it and/or modify             #
# it under the terms of the GNU General Public License as published by     #
# the Free Software Foundation; either version 3 of the License, or        #
# (at your option) any later version.                                      #
#                                                                          #
# This is distributed in the hope that it will be useful,                  #
# but WITHOUT ANY WARRANTY; without even the implied warranty of           #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the            #
# GNU General Public License for more details.                             #
#                                                                          #
# You should have received a copy of the GNU General Public License        #
# along with IPFire; if not, write to the Free Software                    #
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA #
#                                                                          #
# Copyright (C) 2018 - 2019 The IPFire Team                                #
#                                                                          #
############################################################################

use strict;
use warnings;

use lib "/usr/lib/statusmail";

package StatusMail;

use base qw/EncryptedMail/;

require "/var/ipfire/general-functions.pl";
require "${General::swroot}/location-functions.pl";

############################################################################
# Constants
############################################################################

use constant { SEC    => 0,
               MIN    => 1,
               HOUR   => 2,
               MDAY   => 3,
               MON    => 4,
               YEAR   => 5,
               WDAY   => 6,
               YDAY   => 7,
               ISDST  => 8,
               MONSTR => 9 };

use constant MONTHS => qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );

use constant LOGDIR => '/var/log/';

############################################################################
# Configuration variables
############################################################################

my @monthnames    = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                     'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
my %months;

my $max_log_weeks = 52;

############################################################################
# Variables
############################################################################

my %address_lookup_cache;
my @net_addr;
my @net_mask;
my @net_name;

############################################################################
# Function prototypes
############################################################################

sub calculate_period( $$ );
sub get_period_start();
sub get_period_end();
sub get_number_weeks();
sub cache( $;$ );
sub lookup_ip_address( $$ );
sub set_host_name( $$$ );
sub split_string( $$$ );

############################################################################
# Initialisation code
############################################################################


foreach (my $monindex = 0 ; $monindex < MONTHS ; $monindex++)
{
  $months{(MONTHS)[$monindex]} = $monindex;
}

#------------------------------------------------------------------------------
# sub new
#
# Class constructor
#------------------------------------------------------------------------------

sub new
{
  my $invocant = shift;

  my $class = ref($invocant) || $invocant;

  my $self = $class->SUPER::new( @_ );

  $self->{last_when} = 0;
  $self->{last_time} = 0;
  $self->{loc}       = Location::Functions::init();

  bless( $self, $class );

  return $self;
}

#------------------------------------------------------------------------------
# sub calculate_period( value, unit )
#
# Calculates the limits of the period covered by the message
#
# Parameters:
#   value  Number of units
#   unit   Unit of time
#------------------------------------------------------------------------------

sub calculate_period( $$ )
{
  my ( $self, $value, $unit ) = @_;

  use Time::Local;

  my $start_time    = 0;
  my @start_time    = ();
  my $end_time      = 0;
  my @end_time      = ();
  my $weeks_covered = 0;

  my @now        = localtime();
  @end_time      = @now;

  $end_time[SEC] = 0;
  $end_time[MIN] = 0;

  $end_time = timelocal( @end_time );

  if ($unit eq 'months')
  {
    # Go back the specified number of months

    @start_time = @end_time;

    $start_time[MON] -= $value;
    if ($start_time[MON] < 0 )
    {
      $start_time[MON] += 12;
      $start_time[YEAR]--;
    }

    $start_time = timelocal( @start_time );
  }
  else
  {
    my $hours   = $value;

    # Go back the specified number of hours, days or weeks

    $hours     *= 24      if ($unit eq 'days');
    $hours     *= 24 *  7 if ($unit eq 'weeks');

    $start_time = timelocal( @end_time ) - ($hours * 3600);
    @start_time = localtime( $start_time );
  }

  # Adjust end to end of previous hour rather than start of current hour

  $end_time--;
  @end_time = localtime( $end_time );

  # Add the alphabetic month to the end of the time lists

  push @start_time, $monthnames[ $start_time[MON] ];
  push @end_time,   $monthnames[ $end_time[MON] ];

  # Calculate how many archive files have to be read

  my $week_start = $start_time - ($start_time[WDAY] * 86400) - ($start_time[HOUR] * 3600) + 3600;
  $weeks_covered = int( (time() - $week_start) / (86400 * 7) );

  $self->{start_time_array} = \@start_time;
  $self->{start_time}       = $start_time;
  $self->{end_time_array}   = \@end_time;
  $self->{end_time}         = $end_time;
  $self->{weeks_covered}    = $weeks_covered;
  $self->{period}           = "$value$unit";
  $self->{period}           =~ s/s$//;
  $self->{total_days}       = ($end_time - $start_time) / 86400;
}


#------------------------------------------------------------------------------
# sub get_period()
#
# Returns the period covered by a report.
#------------------------------------------------------------------------------

sub get_period()
{
  my $self = shift;

  return $self->{'period'};
}


#------------------------------------------------------------------------------
# sub get_period_start()
#
# Returns the start of the period covered by a report.
#------------------------------------------------------------------------------

sub get_period_start()
{
  my $self = shift;

  return wantarray ? @{$self->{'start_time_array'}} : $self->{'start_time'};
}


#------------------------------------------------------------------------------
# sub get_period_end()
#
# Returns the end of the period covered by a report.
#------------------------------------------------------------------------------

sub get_period_end()
{
  my $self = shift;

  return wantarray ? @{$self->{'end_time_array'}} : $self->{'end_time'};
}


#------------------------------------------------------------------------------
# sub get_number_weeks()
#
# Returns the number of complete weeks covered by a report.
#------------------------------------------------------------------------------

sub get_number_weeks()
{
  my $self = shift;

  return $self->{'weeks_covered'};
}


#------------------------------------------------------------------------------
# sub cache( name [, item] )
#
# Either caches an item or returns the cached item.
#
# Parameters:
#   Name name of item
#   Item item to be cached (optional)
#
# Returns:
#   Cached item if no item specified, undef otherwise
#------------------------------------------------------------------------------

my %cache;

sub cache( $;$ )
{
  my ($self, $name, $item) = @_;

  if ($item)
  {
    $cache{$name} = $item;
  }
  else
  {
    return $cache{$name};
  }

  return undef;
}


#------------------------------------------------------------------------------
# sub clear_cache()
#
# Clears any cached values.
#------------------------------------------------------------------------------

sub clear_cache()
{
  %cache = ();
}


#------------------------------------------------------------------------------
# sub get_message_log_line( logfile, cache )
#
# Gets the next line from the message log.
# Will cache log entries if the period covered is short and cache is true.
#------------------------------------------------------------------------------

sub get_message_log_line
{
  my ($self, $logfile, $cache) = (@_, 1);
  my $line;

  if (exists $self->{$logfile}{logindex})
  {
    # Reading from the cache

    if ($self->{$logfile}{logindex} < @{ $self->{$logfile}{logcache} })
    {
      return $self->{$logfile}{logcache}[$self->{$logfile}{logindex}++];
    }
    else
    {
      # End of cache - reset to start again on next call

      $self->{$logfile}{logindex} = 0;
      return undef;
    }
  }

  # No cache - read from log file

  if (not exists $self->{$logfile}{logfile} or $self->{$logfile}{logfile} < -1)
  {
    # First time reading
    $self->{$logfile}{logfile}  = $max_log_weeks;
    $self->{$logfile}{logcache} = [];
  }

  LINE:
  while (1)
  {
    unless (exists $self->{fh})
    {
      # Need to open a new file

      FILE:
      while ($self->{$logfile}{logfile} > -1)
      {
        my $name = LOGDIR . $logfile;

        $name .= ".$self->{$logfile}{logfile}" if ($self->{$logfile}{logfile} > 0);
        $self->{$logfile}{logfile}--;

        if (-r $name)
        {
          # Not compressed

          my $mtime = (stat( $name ))[9];
          next if ($mtime < $self->{start_time});

          open $self->{fh}, '<', $name or next FILE;
          $self->{year} = (localtime( $mtime ))[YEAR];
          last FILE;
        }
        elsif (-r "$name.gz")
        {
          # Compressed with Gzip

          my $mtime = (stat( "$name.gz" ))[9];
          next if ($mtime < $self->{start_time});

          open $self->{fh}, "gzip -dc $name.gz |" or next FILE;
          $self->{year} = (localtime( $mtime ))[YEAR];
          last FILE;
        }
        elsif (-r "$name.xz")
        {
          # Compressed with XZ

          my $mtime = (stat( "$name.xz" ))[9];
          next if ($mtime < $self->{start_time});

          open $self->{fh}, "xz -dc $name.xz |" or next FILE;
          $self->{year} = (localtime( $mtime ))[YEAR];
          last FILE;
        }

        # Not found - go back for next file

        next FILE;
      }
    }

    unless (defined $self->{fh})
    {
      # No further files - reset to start again on next call

      delete $self->{fh};

      $self->{$logfile}{logfile}  = $max_log_weeks;
      $self->{$logfile}{logindex} = 0 if ($self->{'total_days'} <= 2 and $cache);

      return undef;
    }

    # Reading from a file

    $line = readline $self->{fh};

    unless (defined $line)
    {
      # End of file

      close  $self->{fh};
      delete $self->{fh};

      next LINE;
    }

    next LINE unless ($line);

    my $log_time = $self->_get_log_time( $line );

    # Check to see if we're within the specified limits.
    # Note that the minutes and seconds may be incorrect, but since we only deal
    # in hour boundaries this doesn't matter.

    next LINE if ($log_time < $self->{start_time}); # Earlier - ignore

    if ($log_time > $self->{end_time})
    {
      # After end time - reset to start again on next call

      close $self->{fh};
      delete $self->{fh};
      $self->{$logfile}{logfile}  = $max_log_weeks;
      $self->{$logfile}{logindex} = 0 if ($self->{'total_days'} <= 2 and $cache);

      return undef;
    }

    # Cache the entry if the time covered is two days or less

    push @{$self->{$logfile}{logcache}}, $line if ($self->{'total_days'} <= 2);

    return $line;
  }

  return $line;
}


#------------------------------------------------------------------------------
# sub _get_log_time( line )
#
# Returns the time of a log message
#------------------------------------------------------------------------------

sub _get_log_time
{
  my ($self, $line) = @_;

  my ($when) = substr $line, 0, 15;

  if ($when ne $self->{last_when})
  {
    # Date changed.  Convert to unix time so we can work out whether the
    # message time falls between the limits we're interested in.
    # This is complicated by the lack of a year in the logged information,
    # so assume the current year, and adjust if necessary.

    my @time;

    $time[YEAR] = $self->{year};

    ($time[MON], $time[MDAY], $time[HOUR], $time[MIN], $time[SEC]) = split /[\s:]+/, $line;
    $time[MON] = $months{$time[MON]};

    $self->{time} = timelocal( @time );

    if ($self->{time} > time())
    {
      # We can't have times in the future, so this must be the previous year.

      $self->{year}--;
      $time[YEAR]--;
      $self->{time} = timelocal( @time );
      $self->{last_time} = $self->{time};
    }
    elsif ($self->{time} < $self->{last_time})
    {
      # Time should be increasing, so we must have gone over a year boundary.

      $self->{year}++;
      $time[YEAR]++;
      $self->{time}      = timelocal( @time );
      $self->{last_time} = $self->{time};
    }

    $self->{last_when} = $when;
  }

  return $self->{time};
}


#------------------------------------------------------------------------------
# sub lookup_ip_address( string )
#
# Converts an IP Address to a URL
#------------------------------------------------------------------------------

sub lookup_ip_address( $$ )
{
  my ($self, $address) = @_;

  use Socket;

  return $address_lookup_cache{$address} if (exists $address_lookup_cache{$address});

  my $name = gethostbyaddr( inet_aton( $address ), AF_INET ) || "";

  $address_lookup_cache{$address} = $name;

  return $name;
}


#------------------------------------------------------------------------------
# sub set_host_name( address, name )
#
# Records the mapping from an IP address to a name
#------------------------------------------------------------------------------

sub set_host_name( $$$ )
{
  my ($self, $address, $name) = @_;

  return unless ($address and $name);
  return if ($address eq $name);

  if (exists $address_lookup_cache{$address})
  {
    $address_lookup_cache{$address} = "" if ($address_lookup_cache{$address} ne $name);
  }
  else
  {
    $address_lookup_cache{$address} = $name;
  }
}


#------------------------------------------------------------------------------
# sub spilt_string( string, size )
#
# Splits a string into multiple lf separated lines
#------------------------------------------------------------------------------

sub split_string( $$$ )
{
  my ($self, $string, $size) = @_;

  my $out = '';

  while (length $string > $size)
  {
    $string =~ s/(.{$size,}?)\s+//;
    last unless ($1);
    $out .= $1 . "\n";
  }

  $out .= $string;

  return $out;
}


#------------------------------------------------------------------------------
# sub ip_to_country( ip_address )
#
# Converts an IP address string into a country or network type
#------------------------------------------------------------------------------

sub ip_to_country( $$ )
{
  my ($self, $ip_address) = @_;

  my $country = Location::Functions::lookup_country_code( $self->{loc}, $ip_address );

  return $country if ($country);

  _get_networks() unless ( @net_addr );

  for (my $i = 0 ; $i < @net_addr ; $i++)
  {
    return $net_name[$i] if (General::IpInSubnet( $ip_address, $net_addr[$i], $net_mask[$i] ) );
  }

  # If all else failes, convert to /24 network

  $ip_address =~ s|\d+$|0/24|;

  return $ip_address;
}

#------------------------------------------------------------------------------
# sub _get_networks()
#
# Makes a list of networks
#------------------------------------------------------------------------------

sub _get_networks( $$ )
{
  my %nets;

  # Define local networks

  General::readhash("${General::swroot}/ethernet/settings", \%nets);

  if (exists $nets{GREEN_ADDRESS})
  {
    push @net_addr, $nets{GREEN_ADDRESS};
    push @net_mask, $nets{GREEN_NETMASK};
    push @net_name, $Lang::tr{'green'}
  }

  if (exists $nets{BLUE_ADDRESS})
  {
    push @net_addr, $nets{BLUE_ADDRESS};
    push @net_mask, $nets{BLUE_NETMASK};
    push @net_name, $Lang::tr{'blue'}
  }

  if (exists $nets{ORANGE_ADDRESS})
  {
    push @net_addr, $nets{ORANGE_ADDRESS};
    push @net_mask, $nets{ORANGE_NETMASK};
    push @net_name, $Lang::tr{'orange'}
  }

  # Define RFC 791 special address blocks

#  For some reason the current network check doesn't work
  push @net_addr, "0.0.0.0";         push @net_mask, "255.0.0.0";       push @net_name, "CURRENT NETWORK";
  push @net_addr, "10.0.0.0";        push @net_mask, "255.0.0.0";       push @net_name, "PRIVATE";
  push @net_addr, "100.64.0.0";      push @net_mask, "255.192.0.0";     push @net_name, "CARRIER SHARED";
  push @net_addr, "127.0.0.0";       push @net_mask, "255.0.0.0";       push @net_name, "LOOPBACK";
  push @net_addr, "169.254.0.0";     push @net_mask, "255.255.0.0";     push @net_name, "LINK LOCAL";
  push @net_addr, "172.16.0.0";      push @net_mask, "255.240.0.0";     push @net_name, "PRIVATE";
  push @net_addr, "192.0.0.0";       push @net_mask, "255.255.255.0";   push @net_name, "IETF PROTOCOL";
  push @net_addr, "192.0.2.0";       push @net_mask, "255.255.255.0";   push @net_name, "TEST-NET-1";
  push @net_addr, "192.88.99.0";     push @net_mask, "255.255.255.0";   push @net_name, "RESERVED";
  push @net_addr, "192.168.0.0";     push @net_mask, "255.255.0.0";     push @net_name, "PRIVATE";
  push @net_addr, "192.18.0.0";      push @net_mask, "255.255.254.0";   push @net_name, "BENCHMARK";
  push @net_addr, "192.51.100.0";    push @net_mask, "255.255.255.0";   push @net_name, "TEST-NET-2";
  push @net_addr, "203.0.113.0";     push @net_mask, "255.255.255.0";   push @net_name, "TEST-NET-3";
  push @net_addr, "224.0.0.0";       push @net_mask, "240.0.0.0";       push @net_name, "MULTICAST";
  push @net_addr, "240.0.0.0";       push @net_mask, "240.0.0.0";       push @net_name, "RESERVED";
  push @net_addr, "255.255.255.255"; push @net_mask, "255.255.255.255"; push @net_name, "LIMITED BROADCAST";
}


#------------------------------------------------------------------------------
# sub get_net_interfaces()
#
# Makes a list of network interfaces
#------------------------------------------------------------------------------

sub get_net_interfaces
{
  my $self = shift;

  return @{ $self->{interfaces} } if ($self and exists $self->{Interfaces});

  my %netsettings;

  &General::readhash("${General::swroot}/ethernet/settings", \%netsettings);

  my @interfaces = ( 'green0' );
  my $config_type = $netsettings{'CONFIG_TYPE'};

  if ($netsettings{'RED_TYPE'} ne 'PPPOE')
  {
    if ($netsettings{'RED_DEV'} ne $netsettings{'GREEN_DEV'})
    {
      if ($netsettings{'RED_DEV'} eq 'red0')
      {
        push @interfaces, 'red0';
      }
      else
      {
        push @interfaces, 'ppo0';
      }
    }
  }
  else
  {
    push @interfaces, 'ppp0';
  }

  if ($config_type == 3 or $config_type == 4)
  {
    push @interfaces, 'blue0';
  }

  if ($config_type == 2 or $config_type == 4)
  {
    push @interfaces, 'orange0';
  }

  $self->{interfaces} = [ @interfaces ] if ($self);
  return @interfaces;
}

1;
