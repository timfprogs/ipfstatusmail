#!/usr/bin/perl

############################################################################
#                                                                          #
# Send log and status emails for IPFire                                    #
#                                                                          #
# This is free software; you can redistribute it and/or modify             #
# it under the terms of the GNU General Public License as published by     #
# the Free Software Foundation; either version 2 of the License, or        #
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
# Copyright (C) 2018                                                       #
#                                                                          #
############################################################################

use strict;
use warnings;

use lib "/var/ipfire/statusmail";

package StatusMail;

use base qw/EncryptedMail/;

############################################################################
# Configuration variables
############################################################################

my @monthnames = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');

############################################################################
# Function prototypes
############################################################################

sub calculate_period( $$ );
sub get_period_start();
sub get_period_end();
sub get_weeks_covered();
sub cache( $;$ );

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
    # Go back the specified number of hours, days or weeks

    $value     *= 24      if ($unit eq 'days');
    $value     *= 24 *  7 if ($unit eq 'weeks');

    $start_time = timelocal( @end_time ) - ($value * 3600);
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

1;
