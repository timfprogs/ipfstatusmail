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
# Copyright (C) 2019                                                       #
#                                                                          #
############################################################################

use strict;
use warnings;

use lib "/usr/lib/statusmail";

package StatusMail;

use base qw/EncryptedMail/;

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

use constant LOGNAME => '/var/log/messages';

############################################################################
# Configuration variables
############################################################################

my @monthnames = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug',
                  'Sep', 'Oct', 'Nov', 'Dec');
my %months;

############################################################################
# Variables
############################################################################

my %address_lookup_cache;

############################################################################
# Function prototypes
############################################################################

sub calculate_period( $$ );
sub get_period_start();
sub get_period_end();
sub get_weeks_covered();
sub cache( $;$ );
sub lookup_ip_address( $$ );
sub set_host_name( $$$ );

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

  $self->{last_time} = 0;
  $self->{last_mon}  = 0;
  $self->{last_day}  = 0;
  $self->{last_hour} = 0;

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

  @end_time = localtime();

  $end_time[0] = 0;
  $end_time[1] = 0;

  $end_time = timelocal( @end_time );

  if ($unit eq 'months')
  {
    # Go back the specified number of months

    @start_time = @end_time;

    $start_time[4] -= $value;
    if ($start_time[4] < 0 )
    {
      $start_time[4] += 12;
      $start_time[5]--;
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

  push @start_time, $monthnames[ $start_time[4] ];
  push @end_time,   $monthnames[ $end_time[4] ];

  # Calculate how many archive files have to be read

  my $week_start = $start_time - ($start_time[6] * 86400) - ($start_time[2] * 3600) + 3600;
  $weeks_covered = int( (time() - $week_start) / (86400 * 7) );

  $self->{'start_time_array'} = \@start_time;
  $self->{'start_time'}       = $start_time;
  $self->{'end_time_array'}   = \@end_time;
  $self->{'end_time'}         = $end_time;
  $self->{'weeks_covered'}    = $weeks_covered;
  $self->{'period'}           = "$value$unit";
  $self->{'period'}           =~ s/s$//;
  $self->{'total_days'}       = ($end_time - $start_time) / 86400;
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
# sub get_message_log_line()
#
# Gets the next line from the message log.
# Will cache log entries if the period covered is short.
#------------------------------------------------------------------------------

sub get_message_log_line
{
  my $self = shift;
  my $line;

  if (exists $self->{logindex})
  {
    # Reading from the cache

    if ($self->{logindex} < @{ $self->{logcache} })
    {
      return $self->{logcache}[$self->{logindex}++];
    }
    else
    {
      # End of cache - reset to start again on next call

      $self->{logindex} = 0;
      return undef;
    }
  }

  $self->{logfile} = $self->{'weeks_covered'} if (not exists $self->{logfile} or $self->{logfile} < 0);

  LINE:
  while (1)
  {
    if (not exists $self->{fh} or (exists $self->{fh} and eof $self->{fh}))
    {
      # Reading from a file and need to open a file

      FILE:
      while ($self->{logfile} >= 0)
      {
        my $name = $self->{logfile} < 1 ? LOGNAME : LOGNAME . '.' . $self->{logfile};
        $self->{logfile}--;

        if (-r $name)
        {
          # Not compressed

          open $self->{fh}, '<', $name or die "Can't open $name: $!";
          $self->{year} = (localtime( (stat(_))[9] ))[YEAR];
          last FILE;
        }
        elsif (-r "$name.gz")
        {
          # Compressed

          open $self->{fh}, "gzip -dc $name.gz |" or next;
          $self->{year} = (localtime( (stat(_))[9] ))[YEAR];
          last FILE;
        }

        # Not found - go back for next file
      }

      if ($self->{logfile} < -1)
      {
        # No further files - reset to start again on next call

        delete $self->{fh};
        return undef;
      }
    }

    if (exists $self->{fh})
    {
      # Reading from a file

      $line = readline $self->{fh};

      if (eof $self->{fh})
      {
        if ($self->{logfile} < 0)
        {
          # No further files - reset to start again on next call

          delete $self->{fh};
          return undef;
        }
        # Go back for next file

        close $self->{fh};
        next LINE;
      }

      my ($mon, $day, $hour) = unpack 'Lsxs', $line;

      if ($mon != $self->{last_mon} or $day != $self->{last_day} or $hour != $self->{last_hour})
      {
        # Hour, day or month changed.  Convert to unix time so we can work out
        # whether the message time falls between the limits we're interested in.
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

        ($self->{last_mon}, $self->{last_day}, $self->{last_hour}) = ($mon, $day, $hour);
      }

      # Check to see if we're within the specified limits.
      # Note that the minutes and seconds may be incorrect, but since we only deal
      # in hour boundaries this doesn't matter.

      next LINE if ($self->{time} < $self->{start_time});

      if ($self->{time} > $self->{end_time})
      {
        # After end time - reset to start again on next call

        close $self->{fh};
        delete $self->{fh};
        $self->{logfile} = $self->{'weeks_covered'};

        return undef;
      }

      # Cache the entry if the time covered is less than two days

      push @{$self->{logcache}}, $line if ($self->{'total_days'} <= 2);

      return $line;
    }
  }

  print $line if ($line);
  return $line;
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


1;
