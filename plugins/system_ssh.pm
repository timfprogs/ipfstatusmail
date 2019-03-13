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

package System_Ssh;

use Time::Local;

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'ident'      => 'system-ssh-logins',
                       'section'    => $Lang::tr{'system'},
                       'subsection' => 'SSH',
                       'item'       => $Lang::tr{'statusmail logins'},
                       'function'   => \&logins );

  main::add_mail_item( 'ident'      => 'system-ssh-errors',
                       'section'    => $Lang::tr{'system'},
                       'subsection' => 'SSH',
                       'item'       => $Lang::tr{'statusmail errors'},
                       'function'   => \&errors );
}

############################################################################
# Functions
############################################################################

sub get_log( $ );
sub logins( $$ );
sub errors( $$ );

#------------------------------------------------------------------------------
# sub get_log( this )
#
# Gets log entries for ssh and caches the results
#
# Parameters:
#   this       message object
#
# Returns:
#   Reference to hash of ssh data
#------------------------------------------------------------------------------

sub get_log( $ )
{
  my ($this) = @_;

  my $data = $this->cache( 'ssh' );
  return $data if (defined $data);

  my %info;
  my $line;
  my ($type, $user, $from);

  while ($line = $this->get_message_log_line)
  {
    next unless ($line);
    next unless ($line =~ m/ sshd/);

    if (($type, $user, $from) = $line =~ m/(\w+) password for (?:illegal|invalid user )?(.+) from (.+) port/)
    {
      $info{$type}{"$user||$from"}++;
    }
    elsif (($user, $from) = $line =~ m/Accepted publickey for (.*) from (.*) port/)
    {
      $info{'Accepted'}{"$user||$from"}++;
    }
  }

  $this->cache( 'ssh', \%info );

  return \%info;
}


#------------------------------------------------------------------------------
# sub logins( this )
#
# Outputs information on ssh logins.
#
# Parameters:
#   this       message object
#------------------------------------------------------------------------------

sub logins( $$ )
{
  my ($self) = @_;
  my @table;

  use Sort::Naturally;

  push @table, ['|', '|', '|'];
  push @table, [ $Lang::tr{'user'}, $Lang::tr{'from'}, $Lang::tr{'count'} ];

  my $stats = get_log( $self );

  foreach my $who (sort keys %{ $$stats{'Accepted'} } )
  {
    my $count   = $$stats{'Accepted'}{$who};
    my ($user, $from) = split /\|\|/, $who;

    push @table, [ $user, $from, $count ];
  }

  if (@table > 2)
  {
    $self->add_table( @table );

    return 1;
  }

  return 0;
}


#------------------------------------------------------------------------------
# sub errors( this )
#
# Outputs information on ssh errors.
#
# Parameters:
#   this       message object
#------------------------------------------------------------------------------

sub errors( $$ )
{
  my ($self) = @_;
  my @table;

  use Sort::Naturally;

  push @table, ['|', '|', '|'];
  push @table, [ $Lang::tr{'user'}, $Lang::tr{'from'}, $Lang::tr{'count'} ];

  my $stats = get_log( $self );

  foreach my $who (sort keys %{ $$stats{'Failed'} } )
  {
    my $count   = $$stats{'Failed'}{$who};
    my ($user, $from) = split /\|\|/, $who;

    push @table, [ $user, $from, $count ];
  }

  if (@table > 2)
  {
    $self->add_table( @table );

    return 1;
  }

  return 0;
}

1;
