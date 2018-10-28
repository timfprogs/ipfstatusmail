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

require "${General::swroot}/lang.pl";

use strict;
use warnings;

package Services_Calmav;

use Time::Local;

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  if ( -e "/var/run/clamav/clamd.pid" )
  {
    main::add_mail_item( 'ident'      => 'services-clamav',
                         'section'    => $Lang::tr{'services'},
                         'subsection' => 'Clam AV',
                         'item'       => $Lang::tr{'statusmail ids alerts'},,
                         'function'   => \&alerts );

    main::add_mail_item( 'ident'      => 'services-clamav',
                         'section'    => $Lang::tr{'services'},
                         'subsection' => 'Clam AV',
                         'item'       => $Lang::tr{'updates'},
                         'function'   => \&updates );
  }
}

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

############################################################################
# Functions
############################################################################

sub get_log( $$ );

############################################################################
# Variables
############################################################################

my %months;

#------------------------------------------------------------------------------
# sub get_log( this, name )
#
#
#------------------------------------------------------------------------------

sub get_log( $$ )
{
  my ($this, $name) = @_;

  my $data = $this->cache( 'services-clamav' );
  return $data if (defined $data);

  my %info;
  my $weeks = $this->get_number_weeks;
  my $last_mon   = 0;
  my $last_day   = 0;
  my $last_hour  = 0;
  my $last_time  = 0;
  my $time       = 0;
  my $now        = time();
  my $year       = 0;
  my $start_time = $this->get_period_start;;
  my $end_time   = $this->get_period_end;

  foreach (my $monindex = 0 ; $monindex < MONTHS ; $monindex++)
  {
    $months{(MONTHS)[$monindex]} = $monindex;
  }

  for (my $filenum = $weeks ; $filenum >= 0 ; $filenum--)
  {
    my $filename = $filenum < 1 ? $name : "$name.$filenum";

    if (-r "$filename.gz")
    {
      open IN, "gzip -dc $filename.gz |" or next;
    }
    elsif (-r $filename)
    {
      open IN, '<', $filename or next;
    }
    else
    {
      next;
    }

    $year = (localtime( (stat(_))[9] ))[YEAR];

    foreach my $line (<IN>)
    {
      # We only deal with hour boundaries so check for changes in hour, month, day.
      # This is a hack to quickly check if these fields have changed, without
      # caring about what the values actually are.  We don't care about minutes and
      # seconds.

      my ($mon, $day, $hour) = unpack 'Lsxs', $line;

      if ($mon != $last_mon or $day != $last_day or $hour != $last_hour)
      {
        # Hour, day or month changed.  Convert to unix time so we can work out
        # whether the message time falls between the limits we're interested in.
        # This is complicated by the lack of a year in the logged information.

        my @time;

        $time[YEAR] = $year;

        ($time[MON], $time[MDAY], $time[HOUR], $time[MIN], $time[SEC]) = split /[\s:]+/, $line;
        $time[MON] = $months{$time[MON]};

        $time = timelocal( @time );

        if ($time > $now)
        {
          # We can't have times in the future, so this must be the previous year.

          $year--;my $ports = 0;
          $time[YEAR]--;
          $time      = timelocal( @time );
          $last_time = $time;
        }
        elsif ($time < $last_time)
        {
          # Time is increasing, so we must have gone over a year boundary.

          $year++;
          $time[YEAR]++;
          $time      = timelocal( @time );
          $last_time = $time;
        }

        ($last_mon, $last_day, $last_hour) = ($mon, $day, $hour);
      }

      # Check to see if we're within the specified limits.
      # Note that the minutes and seconds may be incorrect, but since we only deal
      # in hour boundaries this doesn't matter.

      next if ($time < $start_time);
      last if ($time > $end_time);

      next unless ($line =~ m/clamd\[.*\]:|freshclam\[.*\]:/);

      my ($time, $message) = $line =~ m/(\w+\s+\d+\s+\d+:\d+:\d+).*(?:clamd\[.*\]: |freshclam\[.*\]: (.*))/;

      if ($message =~ m/^.+?: (.*?) FOUND/i)
      {
        push @{ $info{viruses} }, [ $time, $message ];
      }
      elsif ($message =~ m/^Database correctly reloaded \((\d+) (?:signatures|viruses)\)/i)
      {
        $info{rules} = $1;
        $info{updates}++;
      }
    }

    close IN;
  }

  $this->cache( 'services-clamav', \%info );

  return \%info;
}

#------------------------------------------------------------------------------

sub alerts( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  use Sort::Naturally;

  push @table, [ $Lang::tr{'time'}, $Lang::tr{'alert'} ];

  my $info = get_log( $self, '/var/log/messages' );

  foreach my $virus ( @{ $$info{viruses} } )
  {
    push @table, $virus;
  }

  if (@table)
  {
    $self->add_table( @table );
  }
}

#------------------------------------------------------------------------------

sub alerts( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  my $info = get_log( $self, '/var/log/messages' );

  if (exists $$info{rules})
  {
    $self->add_text( "\n$Lang::tr{'installed updates'} $$info{updates}" );
    $self->add_text( "\n$Lang::tr{'statusmail signatures'} $$info{rules}" );
  }
}

1;
