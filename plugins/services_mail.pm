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

package Services_mail;

use Time::Local;

############################################################################
# Constants
############################################################################

use constant { SEC    => 0,
               MIN    => 1,
               HOUR   => 2,
               MDAY   => 3,
               MON    => 4,
               YEAR   => 5,
               WDAY   => 6,
               YDAY   => 7,
               ISDST  => 8,
               MONSTR => 9 };

use constant MONTHS => qw( Jan Feb Mar Apr May Jun Jul Aug Sep Oct Nov Dec );

use constant LOGNAME => '/var/log/messages';

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'ident'      => 'services-mail-messages',
                       'section'    => $Lang::tr{'services'},
                       'subsection' => $Lang::tr{'email settings'},
                       'item'       => $Lang::tr{'messages'},
                       'function'   => \&messages );

  main::add_mail_item( 'ident'      => 'services-mail-errors',
                       'section'    => $Lang::tr{'services'},
                       'subsection' => $Lang::tr{'email settings'},
                       'item'       => $Lang::tr{'statusmail errors'},
                       'function'   => \&errors );
}

############################################################################
# Initialisation code
############################################################################

my %months;

foreach (my $monindex = 0 ; $monindex < MONTHS ; $monindex++)
{
  $months{(MONTHS)[$monindex]} = $monindex;
}

############################################################################
# Functions
############################################################################

sub get_log( $ );

#------------------------------------------------------------------------------
# sub get_log( this )
#
# Gets log entries for mail and caches the results
#
# Parameters:
#   this       message object
#
# Returns:
#   Reference to hash of mail data
#------------------------------------------------------------------------------

sub get_log( $ )
{
  my ($this) = @_;

  my $data = $this->cache( 'mail' );

  return $data if (defined $data);

  my %info;
  my $line;
  my %messages;

  while ($line = $this->get_message_log_line( 'mail', 0 ))
  {
    next unless ($line =~ m/ dma/);

    if ($line =~ m/new mail from user=.*? uid=\d+ envelope_from=<.*>/ or
        $line =~ m/trying delivery/ or
        $line =~ m/trying remote delivery to/ or
        $line =~ m/Server greeting successfully completed/ or
        $line =~ m/Server supports STARTTLS/ or
        $line =~ m/Server does not support STARTTLS/ or
        $line =~ m/Server supports CRAM-MD5 authentication/ or
        $line =~ m/Server supports LOGIN authentication/ or
        $line =~ m/SSL initialization successful/ or
        $line =~ m/using SMTP authentication for user / or
        $line =~ m/using smarthost/)
    {
      # Ignore
    }
    elsif ($line =~ m/mail to=<(.*)> queued as .*\.(.*)/)
    {
      if (not exists $info{messages}{$1})
      {
        $info{messages}{$1}{delivered} = 0;
        $info{messages}{$1}{retrys}    = 0;
      }

      $info{messages}{$1}{queued}++;
      $messages{$2} = $1;
    }
    elsif ($line =~ m/dma\[.*\.(.*)\]: <(.*)> delivery successful/)
    {
      $info{messages}{$2}{delivered}++;
      delete $messages{$1};
    }
    elsif ($line =~ m/dma\[.*\.(.*)\]: .* deferred/)
    {
      $info{messages}{$messages{$1}}{retrys}++;
    }
    elsif ($line =~ m/dma\[.*\.(.*)\]: connect to .* failed:/)
    {
      $info{messages}{$messages{$1}}{retrys}++;
    }
    else
    {
      push @{ $info{errors} }, $line;
    }
  }

  $this->cache( 'mail', \%info );

  return \%info;
}


#------------------------------------------------------------------------------
# sub messages( this )
#
# Outputs information on mail messages.
#
# Parameters:
#   this       message object
#------------------------------------------------------------------------------

sub messages
{
  my ($this) = @_;
  my @table;

  use Sort::Naturally;

  push @table, [ $Lang::tr{'to'}, $Lang::tr{'statusmail queued'}, $Lang::tr{'statusmail sent'}, $Lang::tr{'statusmail retries'} ];

  my $stats = get_log( $this );

  foreach my $who (sort keys %{ $$stats{messages} } )
  {
    push @table, [ $who, $$stats{messages}{$who}{queued}, $$stats{messages}{$who}{delivered}, $$stats{messages}{$who}{retrys} ];
  }

  if (@table > 1)
  {
    $this->add_table( @table );

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

sub errors
{
  my ($this) = @_;
  my @table;

  use Sort::Naturally;

  push @table, [ $Lang::tr{'time'}, $Lang::tr{'error'} ];

  my $stats = get_log( $this );

  foreach my $error ( @{ $$stats{errors} } )
  {
    my ($time, $message) = $error =~ m/^(\w+\s+\d+ \d+:\d+\d+).*: (.*)/;

    push @table, [ $time, $message ];
  }

  if (@table > 1)
  {
    $this->add_table( @table );

    return 1;
  }

  return 0;
}

1;
