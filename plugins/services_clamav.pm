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

package Services_Calmav;

use Time::Local;

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  if ( -e "/var/run/clamav/clamd.pid" )
  {
    main::add_mail_item( 'ident'      => 'services-clamav-alerts',
                         'section'    => $Lang::tr{'services'},
                         'subsection' => 'Clam AV',
                         'item'       => $Lang::tr{'statusmail ids alerts'},,
                         'function'   => \&alerts );

    main::add_mail_item( 'ident'      => 'services-clamav-updates',
                         'section'    => $Lang::tr{'services'},
                         'subsection' => 'Clam AV',
                         'item'       => $Lang::tr{'updates'},
                         'function'   => \&updates );
  }
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

  my $data = $this->cache( 'services-clamav' );
  return $data if (defined $data);

  my %info;
  my $line;

  while ($line = $this->get_message_log_line)
  {
    next unless ($line);
    next unless ($line =~ m/clamd\[.*\]:|freshclam\[.*\]:/);

    my ($time, $message) = $line =~ m/\w+\s+(\d+\s+\d+:\d+:\d+).*(?:clamd\[.*\]:|freshclam\[.*\]:) (.*)/;

    if ($message =~ m/^.+?: (.*?) FOUND/i)
    {
      $info{viruses}{$1}++;
    }
    elsif ($message =~ m/^Database correctly reloaded \((\d+) (?:signatures|viruses)\)/i)
    {
      $info{rules} = $1;
      $info{updates}++;
    }
  }

  $this->cache( 'services-clamav', \%info );

  return \%info;
}

#------------------------------------------------------------------------------

sub alerts( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  use Sort::Naturally;

  push @table, [ $Lang::tr{'statusmail ids alert'}, $Lang::tr{'count'} ];

  my $info = get_log( $self );

  foreach my $virus ( sort { $$info{viruses}{$b} <=> $$info{viruses}{$a} || $a cmp $b} keys %{ $$info{viruses} } )
  {
    push @table, [ $virus, $$info{viruses}{$virus} ];
  }

  if (@table > 1)
  {
    $self->add_table( @table );
  }
}

#------------------------------------------------------------------------------

sub updates( $$ )
{
  my ($self, $min_count) = @_;
  my @table;

  my $info = get_log( $self );

  if (exists $$info{rules})
  {
    $self->add_text( "\n$Lang::tr{'installed updates'} $$info{updates}" );
    $self->add_text( "\n$Lang::tr{'statusmail signatures'} $$info{rules}" );
  }
}

1;
