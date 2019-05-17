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

require "${General::swroot}/lang.pl";

use strict;
use warnings;

package Network_Firewall;

use Time::Local;

require "${General::swroot}/geoip-functions.pl";

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'ident'      => 'network-firewall-ipaddresses',
                       'section'    => $Lang::tr{'network'},
                       'subsection' => $Lang::tr{'firewall'},
                       'item'       => $Lang::tr{'ip address'},
                       'function'   => \&addresses,
                       'option'     => { 'type'   => 'integer',
                                         'name'   => $Lang::tr{'statusmail firewall min count'},
                                         'min'    => 1,
                                         'max'    => 1000 } );

  main::add_mail_item( 'ident'      => 'network-firewall-ports',
                       'section'    => $Lang::tr{'network'},
                       'subsection' => $Lang::tr{'firewall'},
                       'item'       => $Lang::tr{port},
                       'function'   => \&ports,
                       'option'     => { 'type'   => 'integer',
                                         'name'   => $Lang::tr{'statusmail firewall min count'},
                                         'min'    => 1,
                                         'max'    => 1000 } );

  main::add_mail_item( 'ident'      => 'network-firewall-countries',
                       'section'    => $Lang::tr{'network'},
                       'subsection' => $Lang::tr{'firewall'},
                       'item'       => $Lang::tr{country},
                       'function'   => \&countries,
                       'option'     => { 'type'   => 'integer',
                                         'name'   => $Lang::tr{'statusmail firewall min count'},
                                         'min'    => 1,
                                         'max'    => 1000 } );

  main::add_mail_item( 'ident'      => 'network-firewall-reason',
                       'section'    => $Lang::tr{'network'},
                       'subsection' => $Lang::tr{'firewall'},
                       'item'       => $Lang::tr{'statusmail firewall reason'},
                       'function'   => \&reasons,
                       'option'     => { 'type'   => 'integer',
                                         'name'   => $Lang::tr{'statusmail firewall min count'},
                                         'min'    => 1,
                                         'max'    => 1000 } );
}


############################################################################
# Functions
############################################################################

sub get_log( $ );
sub addresses( $$ );

#------------------------------------------------------------------------------
# sub get_log( this )
#
# Gets information on blocked packets from the system log and caches it.
#
# Parameters:
#   this  message object
#
# Returns:
#   reference to hash of information
#------------------------------------------------------------------------------

sub get_log( $ )
{
  my ($this, $name) = @_;

  my $data = $this->cache( 'network-firewall' );

  return $data if (defined $data);

  my %info;
  my $line;

  while ($line = $this->get_message_log_line)
  {
    next unless ($line);
    next unless ($line =~ m/kernel: DROP/);

    my ($time, $rule, $interface, $src_addrs, $dst_port) =
        $line =~ m/(\w+\s+\d+\s+\d+:\d+:\d+).*DROP_(\w+?)\s*IN=(\w+).*SRC=(\d+\.\d+\.\d+\.\d+).*(?:DPT=(\d*))/;
# mmm dd hh:mm:dd ipfire kernel: DROP_SPAMHAUS_EDROPIN=ppp0 OUT= MAC= SRC=999.999.999.999 DST=888.888.888.888 LEN=40 TOS=0x00 PREC=0x00 TTL=248 ID=35549 PROTO=TCP SPT=47851 DPT=28672 WINDOW=1024 RES=0x00 SYN URGP=0 MARK=0xd2

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

    $info{'by_rule'}{$rule}{'count'}++;
    $info{'by_rule'}{$rule}{'first'} = $time unless ($info{'by_rule'}{$rule}{'first'});
    $info{'by_rule'}{$rule}{'last'}  = $time;

    $info{'total'}++;
  };

  $this->cache( 'network-firewall', \%info );

  return \%info;
}


#------------------------------------------------------------------------------
# sub addresses( this, min_count )
#
# Output information on blocked addresses.
#
# Parameters:
#   this       message object
#   min_count  only output blocked addresses occurring at least this number of
#              times
#------------------------------------------------------------------------------

sub addresses( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  use Sort::Naturally;

  push @table, ['|', '|', '|', '|', '|', '|'];
  push @table, [ $Lang::tr{'ip address'}, $Lang::tr{'country'}, $Lang::tr{'count'}, $Lang::tr{'percentage'}, $Lang::tr{'first'}, $Lang::tr{'last'} ];

  my $stats = get_log( $self );

  foreach my $address (sort { $$stats{'by_address'}{$b}{'count'} <=> $$stats{'by_address'}{$a}{'count'} ||
                              ncmp( $b, $a ) } keys %{ $$stats{'by_address'} } )
  {
    my $count   = $$stats{'by_address'}{$address}{'count'};
    my $country = GeoIP::lookup( $address );
    my $first   = $$stats{'by_address'}{$address}{'first'};
    my $last    = $$stats{'by_address'}{$address}{'last'};
    my $percent = int( 100 * $count / $$stats{'total'} + 0.5);

    last if ($count < $min_count);

    my $name = $self->lookup_ip_address( $address );

    $address = "$address\n$name" if ($name);

    if ($country)
    {
      $country = GeoIP::get_full_country_name( $country) || $address;
    }
    else
    {
      $country = $Lang::tr{'unknown'};
    }

    push @table, [ $address, $country, $count, $percent, $first, $last ];

    last if (@table > $self->get_max_lines_per_item + 2)
  }

  if (@table > 2)
  {
    $self->add_table( @table );

    return 1;
  }

  return 0;
}


#------------------------------------------------------------------------------
# sub ports( this, min_count )
#
# Output information on blocked ports.
#
# Parameters:
#   this       message object
#   min_count  only output blocked ports occurring at least this number of
#              times
#------------------------------------------------------------------------------

sub ports( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  push @table, ['|', '|', '|', '|', '|'];
  push @table, [ $Lang::tr{'port'}, $Lang::tr{'count'}, $Lang::tr{'percentage'}, $Lang::tr{'first'}, $Lang::tr{'last'} ];

  my $stats = get_log( $self );

  foreach my $port (sort { $$stats{'by_port'}{$b}{'count'} <=> $$stats{'by_port'}{$a}{'count'} ||
                           ncmp( $b, $a ) } keys %{ $$stats{'by_port'} } )
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

    return 1;
  }

  return 0;
}


#------------------------------------------------------------------------------
# sub countries( this, min_count )
#
# Output information on blocked countries.
#
# Parameters:
#   this       message object
#   min_count  only output blocked countries occurring at least this number of
#              times
#------------------------------------------------------------------------------

sub countries( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  push @table, ['<', '|', '|', '|', '|'];
  push @table, [ $Lang::tr{'country'}, $Lang::tr{'count'}, $Lang::tr{'percentage'}, $Lang::tr{'first'}, $Lang::tr{'last'} ];

  my $stats = get_log( $self );

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

    return 1;
  }

  return 0;
}


#------------------------------------------------------------------------------
# sub reasons( this, min_count )
#
# Output information on blocked reasons (the IPtable blocking the packet).
#
# Parameters:
#   this       message object
#   min_count  only output blocked reasons occurring at least this number of
#              times
#------------------------------------------------------------------------------

sub reasons( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  push @table, ['<', '|', '|', '|', '|'];
  push @table, [ $Lang::tr{'statusmail firewall reason'}, $Lang::tr{'count'}, $Lang::tr{'percentage'}, $Lang::tr{'first'}, $Lang::tr{'last'} ];

  my $stats = get_log( $self );

  foreach my $reason (sort { $$stats{'by_rule'}{$b}{'count'} <=> $$stats{'by_rule'}{$a}{'count'} } keys %{ $$stats{'by_rule'} } )
  {
    my $count   = $$stats{'by_rule'}{$reason}{'count'};
    my $first   = $$stats{'by_rule'}{$reason}{'first'};
    my $last    = $$stats{'by_rule'}{$reason}{'last'};
    my $percent = int( 100 * $count / $$stats{'total'} + 0.5);

    last if ($count < $min_count);

    push @table, [ $reason, $count, $percent, $first, $last ];
  }

  if (@table > 2)
  {
    $self->add_table( @table );

    return 1;
  }

  return 0;
}

1;
