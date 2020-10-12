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

package Services_IP_Blacklist_Update;

use Time::Local;

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'ident'      => 'services-ip-blacklist-updates',
                        'section'    => $Lang::tr{'services'},
                        'subsection' => $Lang::tr{'ipblacklist'},
                        'item'       => $Lang::tr{'statusmail update'},
                        'function'   => \&updates );

  main::add_mail_item( 'ident'      => 'services-ip-blocklist-events',
                        'section'    => $Lang::tr{'services'},
                        'subsection' => $Lang::tr{'ipblacklist'},
                        'item'       => $Lang::tr{'statusmail events'},
                        'function'   => \&events );

  main::add_mail_item( 'ident'      => 'services-ip-blacklist-errors',
                        'section'    => $Lang::tr{'services'},
                        'subsection' => $Lang::tr{'ipblacklist'},
                        'item'       => $Lang::tr{'statusmail errors'},
                        'function'   => \&errors );
}

############################################################################
# Functions
############################################################################

sub get_log( $ );

#------------------------------------------------------------------------------
# sub get_log( this )
#
#
#------------------------------------------------------------------------------

sub get_log( $ )
{
  my ($this) = @_;

  my $data = $this->cache( 'services-ipblacklist' );
  return $data if (defined $data);

  my %info;
  my $line;

  while ($line = $this->get_message_log_line( 'messages' ))
  {
    next unless ($line);
    next unless ($line =~ m/^\s*\w+\s+\w+\s+\d+:\d+:\d+\s+\S+ ipblacklist: (.*)/);

    my $text = $1;

    if ($line =~ m/Updated (\w+) blacklist with (\d+) changes/)
    {
      $info{'updates'}{$1}++;
      $info{'changes'}{$1} += $2;
    }
    elsif ($text =~ m/Add IP Address Blacklist update to crontab/    and
           $text =~ m/Enable IP Address Blacklist update in crontab/ and
           $text =~ m/Disable IP Address Blacklist updates/          and
           $text =~ m/Restoring blacklist /                          and
           $text =~ m/Blacklist \w+ changed type/                    and
           $text =~ m/Blacklist \w+ changed size/                    and
           $text =~ m/Enabling IP Blacklist logging/                 and
           $text =~ m/Disabling IP Blacklist logging/ )
    {
      $info{'events'}{$text}++;
    }
    elsif ($text !~ m/Starting IP Blacklists/                        and
           $text !~ m/Starting IP Blacklist processing/              and
           $text !~ m/Stopping IP Blacklists/                        and
           $text !~ m/Deleting IP Blacklists/                        and
           $text !~ m/Finished IP Blacklist processing/              and
           $text !~ m/Create IPTables chains for blacklist/          and
           $text !~ m/Delete IPTables chains for blacklist/ )
    {
      $info{'errors'}{$text}++;
    }
  }

  $this->cache( 'services-ipblacklist', \%info );

  return \%info;
}


#------------------------------------------------------------------------------
# sub updates( this, option )
#
#
#------------------------------------------------------------------------------

sub updates
{
  my ($this) = @_;
  my @table;

  my $info = get_log( $this );

  push @table, [$Lang::tr{'ipblacklist id'}, $Lang::tr{'updates'}, $Lang::tr{'statusmail changes'}];

  foreach my $list ( sort keys %{ $$info{'updates'} } )
  {
    push @table, [ $list, $$info{'updates'}{$list}, $$info{'changes'}{$list} ];
  }

  if (@table > 1)
  {
    $this->add_table( @table );

    return 1;
  }

  return 0;
}


#------------------------------------------------------------------------------
# sub events( this, option )
#
#
#------------------------------------------------------------------------------

sub events
{
  my ($this) = @_;
  my @table;

  my $info = get_log( $this );

  push @table, [$Lang::tr{'statusmail events'}, $Lang::tr{'count'}];

  foreach my $list ( sort keys %{ $$info{'events'} } )
  {
    push @table, [ $list, $$info{'events'}{$list} ];
  }

  if (@table > 1)
  {
    $this->add_table( @table );

    return 1;
  }

  return 0;
}


#------------------------------------------------------------------------------
# sub errors( this, option )
#
#
#------------------------------------------------------------------------------

sub errors
{
  my ($this) = @_;
  my @table;

  my $info = get_log( $this );

  push @table, [$Lang::tr{'statusmail error'}, $Lang::tr{'count'}];

  foreach my $list ( sort keys %{ $$info{'errors'} } )
  {
    push @table, [ $list, $$info{'errors'}{$list} ];
  }

  if (@table > 1)
  {
    $this->add_table( @table );

    return 1;
  }

  return 0;
}

1;
