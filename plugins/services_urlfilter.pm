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

package Services_Urlfilter;

use Time::Local;

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'ident'      => 'services-urlfilter-client',
                       'section'    => $Lang::tr{'services'},
                       'subsection' => $Lang::tr{'urlfilter url filter'},
                       'item'       => $Lang::tr{'urlfilter client'},
                       'function'   => \&clients,
                       'option'     => { 'type'   => 'integer',
                                         'name'   => $Lang::tr{'statusmail urlfilter min count'},
                                         'min'    => 1,
                                         'max'    => 1000 } );

  main::add_mail_item( 'ident'      => 'services-urlfilter-destination',
                       'section'    => $Lang::tr{'services'},
                       'subsection' => $Lang::tr{'urlfilter url filter'},
                       'item'       => $Lang::tr{'destination'},
                       'function'   => \&destinations,
                       'option'     => { 'type'   => 'integer',
                                         'name'   => $Lang::tr{'statusmail urlfilter min count'},
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

  my $data = $this->cache( 'urlfilter' );
  return $data if (defined $data);

  my %info;
  my $weeks = $this->get_number_weeks;
  my @start_time = $this->get_period_start;;
  my @end_time   = $this->get_period_end;

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

    foreach my $line (<IN>)
    {
      my ($year, $mon, $day, $hour) = split /[\s:-]+/, $line;

      # Check to see if we're within the specified limits.
      # Note that the minutes and seconds may be incorrect, but since we only deal
      # in hour boundaries this doesn't matter.

      next if (($year <  ($start_time[YEAR]+1900)) or
               ($year == ($start_time[YEAR]+1900) and $mon <  ($start_time[MON]+1)) or
               ($year == ($start_time[YEAR]+1900) and $mon == ($start_time[MON]+1) and $day <  $start_time[MDAY]) or
               ($year == ($start_time[YEAR]+1900) and $mon == ($start_time[MON]+1) and $day == $start_time[MDAY] and $hour < $start_time[HOUR]));

      last if (($year >  ($end_time[YEAR]+1900)) or
               ($year == ($end_time[YEAR]+1900) and $mon >  ($end_time[MON]+1)) or
               ($year == ($end_time[YEAR]+1900) and $mon == ($end_time[MON]+1) and $day >  $end_time[MDAY]) or
               ($year == ($end_time[YEAR]+1900) and $mon == ($end_time[MON]+1) and $day == $end_time[MDAY] and $hour > $end_time[HOUR]));

      next unless ($line =~ m/Request/);

      if (my ($date, $time, $pid, $type, $destination, $client) = split / /, $line)
      {
        $destination =~ s#^http://|^https://##;
        $destination =~ s/\/.*$//;
        $destination =~ s/:\d+$//;
        my $site = substr( $destination, 0, 69 );
        $site .= "..." if (length( $destination ) > 69);

        my @category = split /\//, $type;

        my ($address, $name) = split "/", $client;

        $this->set_host_name( $address, $name ) unless ($address eq $name);

        $info{'client'}{$address}++;
        $info{'destination'}{"$site||$category[1]"}++;
        $info{'count'}++;
      }
    }

    close IN;
  }

  $this->cache( 'urlfilter', \%info );

  return \%info;
}

#------------------------------------------------------------------------------

sub clients( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  use Sort::Naturally;

  push @table, [ $Lang::tr{'urlfilter client'}, $Lang::tr{'count'} ];

  my $stats = get_log( $self, '/var/log/squidGuard/urlfilter.log' );

  foreach my $client (sort { $$stats{'client'}{$b} <=> $$stats{'client'}{$a} } keys %{ $$stats{'client'} } )
  {
    my $count = $$stats{'client'}{$client};
    last if ($count < $min_count);

    my $host = $self->lookup_ip_address( $client );

    $client .= "\n$host" if ($host);

    push @table, [ $client, $count ];
  }

  if (@table > 1)
  {
    $self->add_table( @table );
  }
}

#------------------------------------------------------------------------------

sub destinations( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  use Sort::Naturally;

  push @table, [ $Lang::tr{'destination'}, $Lang::tr{'urlfilter category'}, $Lang::tr{'count'} ];

  my $stats = get_log( $self, '/var/log/squidGuard/urlfilter.log' );

  foreach my $key (sort { $$stats{'destination'}{$b} <=> $$stats{'destination'}{$a} } keys %{ $$stats{'destination'} } )
  {
    my $count = $$stats{'destination'}{$key};
    last if ($count < $min_count);

    my ($destination, $category) = split /\|\|/, $key;

    push @table, [ $destination, $category, $count ];
  }

  if (@table > 1)
  {
    $self->add_table( @table );
  }
}

1;
