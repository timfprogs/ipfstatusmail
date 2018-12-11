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
#
#------------------------------------------------------------------------------

sub get_log( $ )
{
  my ($this) = @_;

  my $data = $this->cache( 'ssh' );
  return $data if (defined $data);

  my %info;
  my $line;

  while ($line = $this->get_message_log_line)
  {
    next unless ($line);
    next unless ($line =~ m/ sshd/);

    # (Accepted|Failed) password for (root) from (192.168.1.199) port 36868 ssh2
    if (my ($type, $user, $from) = $line =~ m/(\w+) password for (?:illegal|invalid user )?(.+) from (.+) port/)
    {
      $info{$type}{"$user||$from"}++;
    }
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
  }
}

1;
