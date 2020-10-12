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

package Services_Apcups;

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'ident'      => 'services-apcupsd-events',
                        'section'    => $Lang::tr{'services'},
                        'subsection' => 'APC UPS',
                        'item'       => $Lang::tr{'statusmail events'},
                        'function'   => \&ups_events );
}

############################################################################
# Code
############################################################################

#---------------------------------------------------------------------------
# sub ups_events( this )
#
# Output apcupsd events
#
# Parameters:
#   this  message object
#---------------------------------------------------------------------------

sub ups_events
{
  my ($this) = @_;
  my $line;
  my @table;

  push @table, [$Lang::tr{'time'}, $Lang::tr{'statusmail event'}];

  while ($line = $this->get_message_log_line( 'messages' ))
  {
    next unless ($line);
    next unless ($line =~ m/^(\w+\s+\d+ \d+:\d+):\d+ \S+ apcupsd\[\d+\]: (.*)/);

    push @table, [$1, $2];
  }

  if (@table > 1)
  {
    $this->add_table( @table );

    return 1;
  }

  return 0;
}

# Known apcupsd messages
# At the moment none of them are ignored
#
# apcupsd exiting, signal %u
# apcupsd shutdown succeeded
# apcupsd error shutdown completed
# Ignoring --kill-on-powerfail since it is unsafe on Simple Signaling UPSes
# Could not open events file %s: %s
# apcupsd " APCUPSD_RELEASE " (" ADATE ") " APCUPSD_HOST " startup succeeded
# Power failure.
# Running on UPS batteries.
# Battery power exhausted.
# Reached run time limit on batteries.
# Battery charge below low limit.
# Reached remaining time percentage limit on batteries.
# Initiating system shutdown!
# Power is back. UPS running on mains.
# Users requested to logoff.
# Battery failure. Emergency.
# UPS battery must be replaced.
# Remote shutdown requested.
# Communications with UPS lost.
# Communications with UPS restored.
# UPS Self Test switch to battery.
# UPS Self Test completed.
# Mains returned. No longer on UPS batteries.
# Battery disconnected.
# Battery reattached.

1;
