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

use strict;
use warnings;

require "${General::swroot}/lang.pl";

package System_Status_Ps;

############################################################################
# Function prototypes
############################################################################

sub processes( $$ );


############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'ident'      => 'system-status-processes',
                       'section'    => $Lang::tr{'system'},
                       'subsection' => $Lang::tr{'status'},
                       'item'       => $Lang::tr{'processes'},
                       'function'   => \&processes,
                       'option'     => { 'type'   => 'select',
                                         'name'   => $Lang::tr{'user'},
                                         'values' => [ $Lang::tr{'statusmail system ps any'}, 'root', 'nobody', 'squid' ] } );
}

############################################################################
# Code
############################################################################

#------------------------------------------------------------------------------
# sub processes
#
# Adds the current status of the system processes
#------------------------------------------------------------------------------

sub processes( $$ )
{
  my $message = shift;
  my $user    = shift;
  my $cmd     = '';
  my @lines;

  use Sort::Naturally;

  # Convert the option to a switch for the PS command

  if (not $user or $user eq $Lang::tr{'statusmail system ps any'})
  {
    $cmd = 'ps -AF';
  }
  else
  {
    $cmd = "ps -FU $user";
  }

  # Get the process information

  foreach my $line (`$cmd`)
  {
    my @fields = split /\s+/, $line, 11;
    shift @fields unless ($fields[0]);
    push @lines, [ @fields ];
  }

  # Remove the first line so it's not included in the sort

  my $header = shift @lines;

  # Sort the processes in descending order of CPU time

  my @sorted = sort { ncmp( $$b[9], $$a[9] ) } @lines;

  # Put the header row back on

  unshift @sorted, $header;

  if (@sorted > 2)
  {
    $message->add_title( $Lang::tr{'processes'} );
    $message->add_table( @sorted );
  }
}

1;
