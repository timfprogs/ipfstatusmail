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

package statistics_ssh;

use Time::Local;

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'section'    => $Lang::tr{'statusmail statistics'},
                       'subsection' => 'ssh',
                       'item'       => $Lang::tr{'statusmail logins'},
                       'function'   => \&logins );

  main::add_mail_item( 'section'    => $Lang::tr{'statusmail statistics'},
                       'subsection' => 'ssh',
                       'item'       => $Lang::tr{'statusmail errors'},
                       'function'   => \&errors );
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
sub ssh( $ );

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

  my $data = $this->cache( 'ssh' );
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

      next unless ($line =~ m/ipfire sshd/);

      # (Accepted|Failed) password for (root) from (192.168.1.199) port 36868 ssh2
      if (my ($type, $user, $from) = $line =~ m/(\w+) password for (?:illegal|invalid user )?(.+) from (.+) port/)
      {
        $info{$type}{"$user||$from"}++;
      }
    }

    close IN;
  }

  $this->cache( 'ssh', \%info );

  return \%info;
}

#------------------------------------------------------------------------------

sub logins( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  use Sort::Naturally;

  push @table, ['|', '|', '|'];
  push @table, [ $Lang::tr{'user'}, $Lang::tr{'from'}, $Lang::tr{'count'} ];

  my $stats = get_log( $self, '/var/log/messages' );

  foreach my $who (sort keys %{ $$stats{'Accepted'} } )
  {
    my $count   = $$stats{'Accepted'}{$who};
    my ($user, $from) = split /\|\|/, $who;

    push @table, [ $user, $from, $count ];
  }

  if (@table > 2)
  {
    $self->add_table( @table );
  }
}

#------------------------------------------------------------------------------

sub errors( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  use Sort::Naturally;

  push @table, ['|', '|', '|'];
  push @table, [ $Lang::tr{'user'}, $Lang::tr{'from'}, $Lang::tr{'count'} ];

  my $stats = get_log( $self, '/var/log/messages' );

  foreach my $who (sort keys %{ $$stats{'Failed'} } )
  {
    my $count   = $$stats{'Failed'}{$who};
    my ($user, $from) = split /\|\|/, $who;

    push @table, [ $user, $from, $count ];
  }

  if (@table > 2)
  {
    $self->add_table( @table );
  }
}

1;
