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

package statistics_firewall;

use Time::Local;

require "${General::swroot}/geoip-functions.pl";

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'section'    => $Lang::tr{'statusmail statistics'},
                       'subsection' => $Lang::tr{'firewall'},
                       'item'       => $Lang::tr{'ip address'},
                       'function'   => \&addresses,
                       'option'     => { 'type'   => 'integer',
                                         'name'   => $Lang::tr{'statusmail statistics firewall min count'},
                                         'min'    => 1,
                                         'max'    => 1000 } );

  main::add_mail_item( 'section'    => $Lang::tr{'statusmail statistics'},
                       'subsection' => $Lang::tr{'firewall'},
                       'item'       => $Lang::tr{port},
                       'function'   => \&ports,
                       'option'     => { 'type'   => 'integer',
                                         'name'   => $Lang::tr{'statusmail statistics firewall min count'},
                                         'min'    => 1,
                                         'max'    => 1000 } );

  main::add_mail_item( 'section'    => $Lang::tr{'statusmail statistics'},
                       'subsection' => $Lang::tr{'firewall'},
                       'item'       => $Lang::tr{country},
                       'function'   => \&countries,
                       'option'     => { 'type'   => 'integer',
                                         'name'   => $Lang::tr{'statusmail statistics firewall min count'},
                                         'min'    => 1,
                                         'max'    => 1000 } );
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
sub addresses( $$ );

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

  my $data = $this->cache( 'statistics-firewall' );
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

      next unless ($line =~ m/ipfire kernel: DROP/);

      my ($time, $interface, $src_addrs, $dst_port) = $line =~ m/(\w+\s+\d+\s+\d+:\d+:\d+).*IN=(\w+).*SRC=(\d+\.\d+\.\d+\.\d+).*(?:DPT=(\d*))/;
#      Sep  7 15:59:18 ipfire kernel: DROP_SPAMHAUS_EDROPIN=ppp0 OUT= MAC= SRC=146.185.222.28 DST=95.149.139.151 LEN=40 TOS=0x00 PREC=0x00 TTL=248 ID=35549 PROTO=TCP SPT=47851 DPT=28672 WINDOW=1024 RES=0x00 SYN URGP=0 MARK=0xd2

      next unless ($src_addrs);

      my $country = GeoIP::lookup( $src_addrs ) || $src_addrs;

      $info{'by_address'}{$src_addrs}{'count'}++;
      $info{'by_address'}{$src_addrs}{'first'} = $time unless ($info{'by_address'}{$src_addrs}{'first'});
      $info{'by_address'}{$src_addrs}{'last'}  = $time;

      if ($dst_port)
      {
        $info{'by_port'}{$dst_port}{'count'}++ ;
        $info{'by_port'}{$dst_port}{'first'} = $time unless ($info{'by_port'}{$dst_port}{'first'});
        $info{'by_port'}{$dst_port}{'last'}  = $time;
      }

      if ($country)
      {
        $info{'by_country'}{$country}{'count'}++;
        $info{'by_country'}{$country}{'first'} = $time unless ($info{'by_country'}{$country}{'first'});
        $info{'by_country'}{$country}{'last'}  = $time;
      }

      $info{'total'}++;
    }

    close IN;
  }

  $this->cache( 'statistics-firewall', \%info );

  return \%info;
}

#------------------------------------------------------------------------------

sub addresses( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  use Sort::Naturally;

  push @table, ['|', '|', '|', '|', '|', '|'];
  push @table, [ $Lang::tr{'ip address'}, $Lang::tr{'country'}, $Lang::tr{'count'}, $Lang::tr{'percentage'}, $Lang::tr{'first'}, $Lang::tr{'last'} ];

  my $stats = get_log( $self, '/var/log/messages' );

  foreach my $address (sort { $$stats{'by_address'}{$b}{'count'} <=> $$stats{'by_address'}{$a}{'count'} } keys %{ $$stats{'by_address'} } )
  {
    my $count   = $$stats{'by_address'}{$address}{'count'};
    my $country = GeoIP::lookup( $address );
    my $first   = $$stats{'by_address'}{$address}{'first'};
    my $last    = $$stats{'by_address'}{$address}{'last'};
    my $percent = int( 100 * $count / $$stats{'total'} + 0.5);

    last if ($count < $min_count);

    if ($country)
    {
      $country = GeoIP::get_full_country_name( $country) || $address;
    }
    else
    {
      $country = $Lang::tr{'unknown'};
    }

    push @table, [ $address, $country, $count, $percent, $first, $last ];
  }

  if (@table > 2)
  {
    $self->add_table( @table );
  }
}

#------------------------------------------------------------------------------

sub ports( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  push @table, ['|', '|', '|', '|', '|'];
  push @table, [ $Lang::tr{'port'}, $Lang::tr{'count'}, $Lang::tr{'percentage'}, $Lang::tr{'first'}, $Lang::tr{'last'} ];

  my $stats = get_log( $self, '/var/log/messages' );

  foreach my $port (sort { $$stats{'by_port'}{$b}{'count'} <=> $$stats{'by_port'}{$a}{'count'} } keys %{ $$stats{'by_port'} } )
  {
    my $count   = $$stats{'by_port'}{$port}{'count'};
    my $first   = $$stats{'by_port'}{$port}{'first'};
    my $last    = $$stats{'by_port'}{$port}{'last'};
    my $percent = int( 100 * $count / $$stats{'total'} + 0.5);

    last if ($count < $min_count);

    push @table, [ $port, $count, $percent, $first, $last ];
  }

  if (@table > 2)
  {
    $self->add_table( @table );
  }
}

#------------------------------------------------------------------------------

sub countries( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  push @table, ['<', '|', '|', '|', '|'];
  push @table, [ $Lang::tr{'country'}, $Lang::tr{'count'}, $Lang::tr{'percentage'}, $Lang::tr{'first'}, $Lang::tr{'last'} ];

  my $stats = get_log( $self, '/var/log/messages' );

  foreach my $country (sort { $$stats{'by_country'}{$b}{'count'} <=> $$stats{'by_country'}{$a}{'count'} } keys %{ $$stats{'by_country'} } )
  {
    my $count   = $$stats{'by_country'}{$country}{'count'};
    my $first   = $$stats{'by_country'}{$country}{'first'};
    my $last    = $$stats{'by_country'}{$country}{'last'};
    my $percent = int( 100 * $count / $$stats{'total'} + 0.5);

    last if ($count < $min_count);

    my $full_country = GeoIP::get_full_country_name( $country) || $country;

    push @table, [ $full_country, $count, $percent, $first, $last ];
  }

  if (@table > 2)
  {
    $self->add_table( @table );
  }
}

1;
