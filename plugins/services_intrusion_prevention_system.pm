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

require "${General::swroot}/lang.pl";

package Services_Intrusion_Prevention_System;

use Time::Local;

############################################################################
# Function prototypes
############################################################################

sub get_log( $ );

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

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'ident'      => 'services-ips-alerts',
                       'section'    => $Lang::tr{'services'},
                       'subsection' => $Lang::tr{'intrusion detection system'},
                       'item'       => $Lang::tr{'statusmail ips alerts'},
                       'function'   => \&alerts,
                       'option'     => { 'type'   => 'integer',
                                         'name'   => $Lang::tr{'statusmail ips min priority'},
                                         'min'    => 1,
                                         'max'    => 4 } );
}

############################################################################
# Code
############################################################################

#------------------------------------------------------------------------------
# sub get_log
#
#
#------------------------------------------------------------------------------

sub get_log( $ )
{
  my ($this) = @_;

# There's only one data item, so don't use the cache
#  my $data = $this->cache( 'ips-alerts' );
#  return $data if (defined $data);

  my $name = '/var/log/suricata/fast.log';

  my %info;
  my $last_mon   = 0;
  my $last_day   = 0;
  my $last_hour  = 0;
  my $last_time  = 0;
  my $time       = 0;
  my $now        = time();
  my $year       = 0;
  my $start_time = $this->get_period_start;
  my $end_time   = $this->get_period_end;
  my @stats;

  for (my $filenum = $this->get_number_weeks ; $filenum >= 0 ; $filenum--)
  {
    my $filename = $filenum < 1 ? $name : "$name.$filenum";

    if (-r "$filename.gz")
    {
      @stats = stat( _ );
      next if ($stats[9] < $start_time);

      open IN, "gzip -dc $filename.gz |" or next;
    }
    elsif (-r $filename)
    {
      @stats = stat( _ );
      open IN, '<', $filename or next;
    }
    else
    {
      next;
    }

    foreach my $line (<IN>)
    {
      chomp $line;

      # Alerts have the format:
      #
      # mm/dd/yyyy-hh:mm:ss.uuuuuu  [Action] [**] [gid:sid:prio] message [**] [Classification: type] [Priority: prio] {protocol} src-ip:src-port -> dest-ip:dest-port

      $line =~ s/^\s+//;
      $line =~ s/\s+$//;

      next unless ($line);

      my ($mon, $day, $year, $hour, $min, $sec, $gid, $sid, $message, $prio, $src, $dest) =
        $line =~ m|(\d+)/(\d+)/(\d+)-(\d+):(\d+):(\d+)\.\d+\s+\[\w+\]\s+\[\*\*\]\s+\[(\d+):(\d+):\d+\]\s*(.*)\s+\[\*\*\].*\[Priority:\s(\d+)\].*?\s+(\d+\.\d+\.\d+\.\d+(?::\d+)?) -> (\d+\.\d+\.\d+\.\d+(?::\d+)?)|;

      $sid = "$gid-$sid";

      if ($mon != $last_mon or $day != $last_day or $hour != $last_hour)
      {
        # Hour, day or month changed.  Convert to unix time so we can work out
        # whether the message time falls between the limits we're interested in.

        my @time;

        $time[YEAR] = $year;

        ($time[MON], $time[MDAY], $time[HOUR], $time[MIN], $time[SEC]) = ($mon - 1, $day, $hour, $min, $sec);

        $time = timelocal( @time );

        ($last_mon, $last_day, $last_hour) = ($mon, $day, $hour);
      }

      # Check to see if we're within the specified limits.
      # Note that the minutes and seconds may be incorrect, but since we only deal
      # in hour boundaries this doesn't matter.

      next if ($time < $start_time);
      last if ($time > $end_time);

      my $timestr = "$mon/$day $hour:$min:$sec";

      $info{total}++;

      if (exists $info{by_sid}{$sid})
      {
        $info{by_sid}{$sid}{count}++;
        $info{by_sid}{$sid}{last}    = $timestr;
      }
      else
      {
        $info{by_sid}{$sid}{count}    = 1;
        $info{by_sid}{$sid}{priority} = $prio;
        $info{by_sid}{$sid}{message}  = $message;
        $info{by_sid}{$sid}{first}    = $timestr;
        $info{by_sid}{$sid}{last}     = $timestr;
      }
    }

    close IN;
  }

#  $this->cache( 'ids-alerts', \%info );

  return \%info;

}


#------------------------------------------------------------------------------

sub alerts( $$ )
{
  my ($self, $min_priority) = @_;
  my @table;

  use Sort::Naturally;

  push @table, ['|', '|', '<', '|', '|', '|', '|'];
  push @table, [ 'SID', $Lang::tr{'priority'}, $Lang::tr{'name'}, $Lang::tr{'count'}, $Lang::tr{'percentage'}, $Lang::tr{'first'}, $Lang::tr{'last'} ];

  my $stats = get_log( $self );

  foreach my $sid (sort { $$stats{by_sid}{$a}{priority} <=> $$stats{by_sid}{$b}{priority} ||
                          $$stats{by_sid}{$b}{count} <=> $$stats{by_sid}{$a}{count}} keys %{ $$stats{by_sid} } )
  {
    my $message  = $$stats{by_sid}{$sid}{message};
    my $priority = $$stats{by_sid}{$sid}{priority};
    my $count    = $$stats{by_sid}{$sid}{count};
    my $first    = $$stats{by_sid}{$sid}{first};
    my $last     = $$stats{by_sid}{$sid}{last};
    my $percent  = int( 100 * $count / $$stats{total} + 0.5);

    last if ($priority > $min_priority);
    
    $message = $self->split_string( $message, 40 );

    push @table, [ $sid, $priority, $message, $count, $percent, $first, $last ];
  }

  if (@table > 2)
  {
    $self->add_table( @table );
    
    return 1;
  }
  
  return 0;
}


1;
