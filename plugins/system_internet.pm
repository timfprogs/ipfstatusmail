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

use strict;
#use warnings;

require "${General::swroot}/lang.pl";

package System_Internet;

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'ident'      => 'services-internet-events',
                       'section'    => $Lang::tr{'system'},
                       'subsection' => $Lang::tr{'red'},
                       'item'       => $Lang::tr{'statusmail events'},
                       'function'   => \&events );
}

############################################################################
# Code
############################################################################

#---------------------------------------------------------------------------
# sub events( this )
#
# Output internet events
#
# Parameters:
#   this  message object
#---------------------------------------------------------------------------

sub events
{
  my ($this) = @_;
  my $line;
  my @table;

  push @table, [$Lang::tr{'time'}, $Lang::tr{'statusmail event'}];

  while ($line = $this->get_message_log_line( 'messages' ))
  {
    next unless ($line);
    next unless ($line =~ m/^(\w+\s+\d+ \d+:\d+):\d+ \S+ (red|pppd\[.*\]: |chat\[.*\]|pppoe\[.*\]|pptp\[.*\]|pppoa\[.*\]|pppoa3\[.*\]|pppoeci\[.*\]|ipppd|ipppd\[.*\]|kernel: ippp\d|kernel: isdn.*|ibod\[.*\]|dhcpcd\[.*\]|modem_run\[.*\])(.*)/);

    my ($time, $what, $message) = ($1, $2, $3);

    next if ($what =~ m/dhcpcd/ and $message !~ m/carrier/);

    push @table, [$time, $message];
  }

  if (@table > 1)
  {
    $this->add_table( @table );

    return 1;
  }

  return 0;
}

1;
