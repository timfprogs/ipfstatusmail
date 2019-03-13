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
# Copyright (C) 2019                                                       #
#                                                                          #
############################################################################

require "${General::swroot}/lang.pl";

use strict;
use warnings;

package Services_Blocklist_Update;

use Time::Local;

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  if (-d "/var/ipfire/blocklist")
  {
    main::add_mail_item( 'ident'      => 'services-ip-blocklist',
                         'section'    => $Lang::tr{'services'},
                         'subsection' => $Lang::tr{'blocklists'},
                         'item'       => $Lang::tr{'statusmail blocklist update'},
                         'function'   => \&updates );

    main::add_mail_item( 'ident'      => 'services-ip-blocklist',
                         'section'    => $Lang::tr{'services'},
                         'subsection' => $Lang::tr{'blocklists'},
                         'item'       => $Lang::tr{'statusmail errors'},
                         'function'   => \&errors );
  }
}

############################################################################
# Functions
############################################################################

sub updates( $ );
sub errors( $ );
sub get_log( $ );

#------------------------------------------------------------------------------
# sub get_log( this )
#
# Gets information on IP Blocklist updates from the system log and caches it.
#
# Parameters:
#   this  message object
#
# Returns:
#   reference to hash of information
#------------------------------------------------------------------------------

sub get_log( $ )
{
  my ($this) = @_;

  my $data = $this->cache( 'services-blocklist' );
  return $data if (defined $data);

  my %info;
  my $line;

  while ($line = $this->get_message_log_line)
  {
    next unless ($line);
    next unless ($line =~ m/^\s*\w+\s+\w+\s+\d+:\d+:\d+\s+\S+ blocklist: (.*)/);

    my $text = $1;

    if ($line =~ m/Updating (\w+) blocklist/)
    {
      $info{'updates'}{$1}++;
    }
    elsif ($line !~ m/Blocklist (\w+) Modification times/   and
           $line !~ m/Starting IP Blocklist processing/     and
           $line !~ m/Completed IP Blocklist update/        and
           $line !~ m/Create IPTables chains for blocklist/ and
           $line !~ m/Delete IPTables chains for blocklist/)
    {
      $info{'errors'}{$text}++
    }
  }

  $this->cache( 'services-blocklist', \%info );

  return \%info;
}


#------------------------------------------------------------------------------
# sub updates( this )
#
# Outputs information on blocklist updates.
#
# Parameters:
#   this  message object
#------------------------------------------------------------------------------

sub updates( $ )
{
  my ($this) = @_;
  my @table;

  my $info = get_log( $this );

  push @table, ['blocklist', $Lang::tr{'count'}];

  foreach my $list ( sort keys %{ $$info{'updates'} } )
  {
    push @table, [ $list, $$info{'updates'}{$list} ];
  }

  if (@table > 1)
  {
    $this->add_table( @table );

    return 1;
  }

  return 0
}


#------------------------------------------------------------------------------
# sub errors( this )
#
# Outputs information on blocklist update errors.
#
# Parameters:
#   this  message object
#------------------------------------------------------------------------------

sub errors( $ )
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
