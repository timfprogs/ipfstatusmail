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

package Services_IDS_Update;

use Time::Local;

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  if (-d "/var/ipfire/idsupdate")
  {
    main::add_mail_item( 'ident'      => 'services-ids-update',
                        'section'    => $Lang::tr{'services'},
                        'subsection' => $Lang::tr{'intrusion detection system'},
                        'item'       => $Lang::tr{'statusmail ids update'},
                        'function'   => \&updates,
                        'option'     => { 'type'   => 'select',
                                          'name'   => $Lang::tr{'statusmail detail'},
                                          'values' => [ "$Lang::tr{'statusmail summary'}:summary",
                                                        "$Lang::tr{'statusmail full'}:full" ] } );
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

sub updates( $$ );
sub show_table( $$$@ );

############################################################################
# Variables
############################################################################

my %months;

#------------------------------------------------------------------------------
# sub updates( this, option )
#
#
#------------------------------------------------------------------------------

sub updates( $$ )
{
  my ($this, $option) = @_;
  my @table;
  my %updates;
  my @new_enabled;
  my @new_disabled;
  my @deleted;
  my @consider_enable;
  my @consider_disable;
  my @enabled;
  my @disabled;
  my $active_rules = -1;
  my %unrecognised;

  my $weeks      = $this->get_number_weeks;
  my $last_mon   = 0;
  my $last_day   = 0;
  my $last_hour  = 0;
  my $last_time  = 0;
  my $time       = 0;
  my $now        = time();
  my $year       = 0;
  my $start_time = $this->get_period_start;;
  my $end_time   = $this->get_period_end;
  my $name       = "/var/log/messages";

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

      next unless ($line =~ m/^(.*) ipfire idsupdate: (.*)/);

      my $time = $1;

      if ($line =~ m/Completed update:\s*(\d+)/)
      {
        $active_rules = $1;
      }
      elsif ($line =~ m/Download (.+) rules/)
      {
        $updates{$1}++;
      }
      elsif ($line =~ m/Enabled new rule sid:(\d+) (.+)/)
      {
        push @new_enabled, [ $1, $2 ];
      }
      elsif ($line =~ m/Deleted rule sid:(\d+) (.+)/)
      {
        push @deleted, [ $1, $2 ];
      }
      elsif ($line =~ m/Enabled rule sid:(\d+) changed ([\w_-]+) from ([\w_-]+) to ([\w_-]+)\s+(.+)/)
      {
        push @consider_disable, [ $1, $2, $3, $4, $5 ];
      }
      elsif ($line =~ m/Disabled rule sid:(\d+) changed ([\w_-]+) from ([\w_-]+) to ([\w_-]+)\s+(.+)/)
      {
        push @consider_enable, [$1, $2, $3, $4, $5 ];
      }
      elsif ($line =~ m/Disabled new rule sid:(\d+) (.+)/)
      {
        push @new_disabled, [ $1, $2 ];
      }
      elsif ($line =~ m/Enabled rule sid:(\d+) due to changed ([\w_-]+) from ([\w_-]+) to ([\w_-]+)\s+(.+)/)
      {
        push @enabled, [ $1, $2, $3, $4, $5 ];
      }
      elsif ($line =~ m/Disabled rule sid:(\d+) due to changed ([\w_-]+) from ([\w_-]+) to ([\w_-]+)\s+(.+)/)
      {
        push @disabled, [ $1, $2, $3, $4, $5 ];
      }
      elsif ($line !~ m/Starting Snort update check|No updates available|Checking that Snort is running correctly/ and
             $line !~ m/Getting current rule state|Updating.*rules|Getting rule changes|Writing new update/        and
             $line !~ m/Telling Snort pid \d+ to re-read rules|Stopping Snort|Starting Snort/)
      {
        $unrecognised{$2}++;
      }

    }

    close IN;
  }

  if (%updates)
  {
    my @table;

    $this->add_title( $Lang::tr{'statusmail update'} );

    push @table, [ $Lang::tr{'idsupdate ruleset'}, $Lang::tr{'count'} ];

    foreach my $ruleset (sort keys %updates)
    {
      push @table, [ $ruleset, $updates{$ruleset} ] ;
    }

    $this->add_table( @table );
  }

  $this->add_text( "\n$Lang::tr{'idsupdate active rules'} $active_rules" ) if ($active_rules > -1);

  if (%unrecognised)
  {
    my @table;

    $this->add_title( $Lang::tr{'idsupdate unrecognised log messages'} );

    push @table, [ $Lang::tr{'statusmail error'}, $Lang::tr{'count'} ];

    foreach my $error (sort { $unrecognised{$b} <=> $unrecognised{$a} || $a cmp $b } keys %unrecognised)
    {
      push @table, [ $error, $unrecognised{$error} ] ;
    }

    $this->add_table( @table );
  }

  return unless ($option eq 'full');

  # -- New rules

  show_table( $this, $Lang::tr{'idsupdate enabled'}, "SID||$Lang::tr{'name'}", @new_enabled );
  show_table( $this, $Lang::tr{'idsupdate disabled'}, "SID||$Lang::tr{'name'}", @new_disabled );

  # -- Deleted rules

  show_table( $this, $Lang::tr{'idsupdate deleted rules'}, "SID||$Lang::tr{'name'}", @deleted );

  #-- Changed rules

  show_table( $this,
              $Lang::tr{'idsupdate changed enabled'},
              "SID||$Lang::tr{'idsupdate change'}||$Lang::tr{'idsupdate from'}||$Lang::tr{'idsupdate to'}||$Lang::tr{'name'}",
              @consider_disable );

  show_table( $this,
              $Lang::tr{'idsupdate changed disabled'},
              "SID||$Lang::tr{'idsupdate change'}||$Lang::tr{'idsupdate from'}||$Lang::tr{'idsupdate to'}||$Lang::tr{'name'}",
              @consider_enable );

  show_table( $this,
              $Lang::tr{'idsupdate enabled'},
              "SID||$Lang::tr{'idsupdate change'}||$Lang::tr{'idsupdate from'}||$Lang::tr{'idsupdate to'}||$Lang::tr{'name'}",
              @enabled );

  show_table( $this,
              $Lang::tr{'idsupdate disabled'},
              "SID||$Lang::tr{'idsupdate change'}||$Lang::tr{'idsupdate from'}||$Lang::tr{'idsupdate to'}||$Lang::tr{'name'}",
              @disabled );
}

sub show_table( $$$@ )
{
  my ($this, $title, $heading, @items) = @_;

  return unless (@items);

  $this->add_title( $title );

  @items = sort { $a->[0] <=> $b->[0] } @items;

  my @header = split /\|\|/, $heading;

  unshift @items, [ @header ];

  $this->add_table( @items );
}

1;
