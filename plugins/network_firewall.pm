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
#use warnings;

require "${General::swroot}/lang.pl";

package Network_Firewall;

use Time::Local;
use Sort::Naturally;
use lib "/usr/lib/statusmail";

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  use StatusMail;

  my %common_options = ( 'section'    => $Lang::tr{'network'},
                         'subsection' => $Lang::tr{'firewall'},
                         'option'     => { 'type'   => 'integer',
                                           'name'   => $Lang::tr{'statusmail firewall min count'},
                                           'min'    => 1,
                                           'max'    => 1000 } );

  foreach my $interface ( StatusMail::get_net_interfaces() )
  {
    main::add_mail_item( %common_options,
                         'ident'      => 'network-firewall-ipaddresses-' . $interface,
                         'item'       => "$Lang::tr{'ip address'} - $interface",
                         'function'   => \&addresses,
                         'param'      => $interface );

    main::add_mail_item( %common_options,
                         'ident'      => 'network-firewall-ports-' . $interface,
                         'item'       => "$Lang::tr{'port'} - $interface",
                         'function'   => \&ports,
                         'param'      => $interface );

    main::add_mail_item( %common_options,
                         'ident'      => 'network-firewall-countries-' . $interface,
                         'item'       => "$Lang::tr{country} - $interface",
                         'function'   => \&countries,
                         'param'      => $interface );

    main::add_mail_item( %common_options,
                         'ident'      => 'network-firewall-reason-' . $interface,
                         'item'       => "$Lang::tr{'statusmail firewall reason'} - $interface",
                         'function'   => \&reasons,
                         'param'      => $interface );
  }
}


############################################################################
# Functions
############################################################################

sub get_log( $ );

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

  while ($line = $this->get_message_log_line( 'messages' ))
  {
    next unless ($line =~ m/kernel: .*IN=/);

    my ($time, $rule, $interface, $src_addrs, $dst_port) =
        $line =~ m/(\w+\s+\d+\s+\d+:\d+):\d+.*kernel: (.*)\s*IN=(\w+).*SRC=(\d+\.\d+\.\d+\.\d+).*(?:DPT=(\d*))/;
# mmm dd hh:mm:dd ipfire kernel: BLKLST_SPAMHAUS_EDROPIN=ppp0 OUT= MAC= SRC=999.999.999.999 DST=888.888.888.888 LEN=40 TOS=0x00 PREC=0x00 TTL=248 ID=35549 PROTO=TCP SPT=47851 DPT=28672 WINDOW=1024 RES=0x00 SYN URGP=0 MARK=0xd2

    next unless ($src_addrs);

    my $country = $this->ip_to_country( $src_addrs );

    $info{'by_address'}{$interface}{$src_addrs}{'count'}++;
    $info{'by_address'}{$interface}{$src_addrs}{'first'} = $time unless ($info{'by_address'}{$interface}{$src_addrs}{'first'});
    $info{'by_address'}{$interface}{$src_addrs}{'last'}  = $time;

    if ($dst_port)
    {
      $info{'by_port'}{$interface}{$dst_port}{'count'}++ ;
      $info{'by_port'}{$interface}{$dst_port}{'first'} = $time unless ($info{'by_port'}{$interface}{$dst_port}{'first'});
      $info{'by_port'}{$interface}{$dst_port}{'last'}  = $time;
    }

    if ($country)
    {
      $info{'by_country'}{$interface}{$country}{'count'}++;
      $info{'by_country'}{$interface}{$country}{'first'} = $time unless ($info{'by_country'}{$interface}{$country}{'first'});
      $info{'by_country'}{$interface}{$country}{'last'}  = $time;
    }

    $info{'by_rule'}{$interface}{$rule}{'count'}++;
    $info{'by_rule'}{$interface}{$rule}{'first'} = $time unless ($info{'by_rule'}{$interface}{$rule}{'first'});
    $info{'by_rule'}{$interface}{$rule}{'last'}  = $time;

    $info{'total'}{$interface}++;
  };

  $this->cache( 'network-firewall', \%info );

  return \%info;
}


#------------------------------------------------------------------------------
# sub addresses( this, interface, min_count )
#
# Output information on blocked addresses.
#
# Parameters:
#   this       message object
#   interface  nextwork interface
#   min_count  only output blocked addresses occurring at least this number of
#              times
#------------------------------------------------------------------------------

sub addresses
{
  my ($self, $interface, $min_count) = @_;
  my $retv = 0;

  my $stats = get_log( $self );

  my @table;

  $self->add_title( "$Lang::tr{'ip address'} - $interface" );
  push @table, ['|', '|', '#', '#', '|', '|'];
  push @table, [ $Lang::tr{'ip address'}, $Lang::tr{'country'}, $Lang::tr{'count'}, '%', $Lang::tr{'first'}, $Lang::tr{'last'} ];

  foreach my $address (sort { $$stats{'by_address'}{$interface}{$b}{'count'} <=> $$stats{'by_address'}{$interface}{$a}{'count'} ||
                              ncmp( $b, $a ) } keys %{ $$stats{'by_address'}{$interface} } )
  {
    my $count   = $$stats{'by_address'}{$interface}{$address}{'count'};
    my $country = $self->ip_to_country( $address );
    my $first   = $$stats{'by_address'}{$interface}{$address}{'first'};
    my $last    = $$stats{'by_address'}{$interface}{$address}{'last'};
    my $percent = int( 100 * $count / $$stats{'total'}{$interface} + 0.5);

    last if ($count < $min_count);

    my $name = $self->lookup_ip_address( $address );

    $address = "$address\n$name" if ($name);

    $country = Location::Functions::get_full_country_name( $country) || $country;

    push @table, [ $address, $country, $count, $percent, $first, $last ];

    last if (@table > $self->get_max_lines_per_item + 2)
  }

  if (@table > 2)
  {
    $self->add_table( @table );

    $retv = 1;
  }

  return $retv;
}


#------------------------------------------------------------------------------
# sub ports( this, interface, min_count )
#
# Output information on blocked ports.
#
# Parameters:
#   this       message object
#   interface  nextwork interface
#   min_count  only output blocked ports occurring at least this number of
#              times
#------------------------------------------------------------------------------

sub ports( $$$ )
{
  my ($self, $interface, $min_count) = @_;
  my $retv = 0;

  my $stats = get_log( $self );

  my @table;

  $self->add_title( "$Lang::tr{'port'} - $interface" );
  push @table, ['|', '#', '#', '|', '|'];
  push @table, [ $Lang::tr{'port'}, $Lang::tr{'count'}, '%', $Lang::tr{'first'}, $Lang::tr{'last'} ];

  foreach my $port (sort { $$stats{'by_port'}{$interface}{$b}{'count'} <=> $$stats{'by_port'}{$interface}{$a}{'count'} ||
                          ncmp( $b, $a ) } keys %{ $$stats{'by_port'}{$interface} } )
  {
    my $count   = $$stats{'by_port'}{$interface}{$port}{'count'};
    my $first   = $$stats{'by_port'}{$interface}{$port}{'first'};
    my $last    = $$stats{'by_port'}{$interface}{$port}{'last'};
    my $percent = int( 100 * $count / $$stats{'total'}{$interface} + 0.5);

    last if ($count < $min_count);

    push @table, [ $port, $count, $percent, $first, $last ];
  }

  if (@table > 2)
  {
    $self->add_table( @table );

    $retv = 1;
  }

  return $retv;
}


#------------------------------------------------------------------------------
# sub countries( this, interface, min_count )
#
# Output information on blocked countries.
#
# Parameters:
#   this       message object
#   interface  nextwork interface
#   min_count  only output blocked countries occurring at least this number of
#              times
#------------------------------------------------------------------------------

sub countries( $$$ )
{
  my ($self, $interface, $min_count) = @_;
  my $retv = 0;

  my $stats = get_log( $self );

  my @table;

  $self->add_title( "$Lang::tr{'country'} - $interface" );
  push @table, ['<', '#', '#', '|', '|'];
  push @table, [ $Lang::tr{'country'}, $Lang::tr{'count'}, '%', $Lang::tr{'first'}, $Lang::tr{'last'} ];


  foreach my $country (sort { $$stats{'by_country'}{$interface}{$b}{'count'} <=> $$stats{'by_country'}{$interface}{$a}{'count'} } keys %{ $$stats{'by_country'}{$interface} } )
  {
    my $count   = $$stats{'by_country'}{$interface}{$country}{'count'};
    my $first   = $$stats{'by_country'}{$interface}{$country}{'first'};
    my $last    = $$stats{'by_country'}{$interface}{$country}{'last'};
    my $percent = int( 100 * $count / $$stats{'total'}{$interface} + 0.5);

    last if ($count < $min_count);

    my $full_country = Location::Functions::get_full_country_name( $country) || $country;

    push @table, [ $full_country, $count, $percent, $first, $last ];
  }

  if (@table > 2)
  {
    $self->add_table( @table );

    $retv = 1;
  }

  return $retv;
}


#------------------------------------------------------------------------------
# sub reasons( this, interface, min_count )
#
# Output information on blocked reasons (the IPtable blocking the packet).
#
# Parameters:
#   this       message object
#   interface  nextwork interface
#   min_count  only output blocked reasons occurring at least this number of
#              times
#------------------------------------------------------------------------------

sub reasons( $$$ )
{
  my ($self, $interface, $min_count) = @_;
  my $retv = 0;

  my $stats = get_log( $self );

  my @table;

  $self->add_title( "$Lang::tr{'statusmail firewall reason'} - $interface" );
  push @table, ['<', '#', '#', '|', '|'];
  push @table, [ $Lang::tr{'statusmail firewall reason'}, $Lang::tr{'count'}, '%', $Lang::tr{'first'}, $Lang::tr{'last'} ];

  foreach my $reason (sort { $$stats{'by_rule'}{$interface}{$b}{'count'} <=> $$stats{'by_rule'}{$interface}{$a}{'count'} } keys %{ $$stats{'by_rule'}{$interface} } )
  {
    my $count   = $$stats{'by_rule'}{$interface}{$reason}{'count'};
    my $first   = $$stats{'by_rule'}{$interface}{$reason}{'first'};
    my $last    = $$stats{'by_rule'}{$interface}{$reason}{'last'};
    my $percent = int( 100 * $count / $$stats{'total'}{$interface} + 0.5);

    last if ($count < $min_count);

    push @table, [ $reason, $count, $percent, $first, $last ];
  }

  if (@table > 2)
  {
    $self->add_table( @table );

    $retv = 1;
  }

  return $retv;
}

1;
