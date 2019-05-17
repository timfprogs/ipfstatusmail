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

require "${General::swroot}/lang.pl";

use strict;
use warnings;

package System_Kernel;

use Time::Local;

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'ident'      => 'system-kernel-alerts',
                       'section'    => $Lang::tr{'system'},
                       'subsection' => $Lang::tr{'kernel'},
                       'item'       => $Lang::tr{'statusmail errors'},
                       'function'   => \&errors );
}


############################################################################
# Functions
############################################################################

sub get_log( $ );
sub errors( $ );

#------------------------------------------------------------------------------
# sub get_log( this )
#
# Gets kernel messages from the system log.
#
# Parameters:
#   this  message object
#------------------------------------------------------------------------------

sub get_log( $ )
{
  my ($this) = @_;

# Comment out since there's only one item at the moment
# my $data = $this->cache( 'system-kernel' );
# return $data if (defined $data);

  my %info;
  my $line;

  while ($line = $this->get_message_log_line)
  {
    next unless ($line);
    next unless ($line =~ m/ kernel: /);
    next if ($line =~ m/ kernel: DROP_/);

    if ( my ($from, $if) = $line =~ m/^Warning: possible SYN flood from ([^ ]+) on ([^ ]+):.+ Sending cookies/ )
    {
      $info{SYNflood}{$from}{$if}++;
    }
    elsif ($line =~ m/continuing in degraded mode/)
    {
      $info{RAIDErrors}{$line}++;
    }
    elsif ($line =~ m/([^(]*)\[\d+\]: segfault at/)
    {
      $info{SegFaults}{$1}++;
    }
    elsif ($line =~ m/([^(]*)\[\d+\] general protection/)
    {
      $info{GPFaults}{$1}++;
    }
    elsif ($line =~ m/([^(]*)\[\d+\] trap int3 /)
    {
      $info{TrapInt3s}{$1}++;
    }
    elsif ($line =~ m/([^(]*)\(\d+\): unaligned access to/)
    {
      $info{UnalignedErrors}{$1}++;
    }
    elsif ($line =~ /([^(]*)\(\d+\): floating-point assist fault at ip/)
    {
      $info{FPAssists}{$1}++;
    }
    elsif ($line =~ m/Out of memory: Killed process \d+ \((.*)\)/)
    {
      $info{OOM}{$1}++;
    }
    elsif ($line =~ m/(\S+) invoked oom-killer/)
    {
      $info{OOM}{$1}++;
    }
    elsif ($line =~ m/(EDAC (MC|PCI)\d:.*)/)
    {
      # Standard boot messages
      next if ($line =~ m/Giving out device to /);
      $info{EDAC}{$1}++;
    }
    elsif ( ( my $errormsg ) = ( $line =~ m/((BUG|WARNING|INFO):.{0,40})/ ) )
    {
      $info{Errors}{$errormsg}++;
    }
  }

# $this->cache( 'system-kernel', \%info );

  return \%info;
}

#------------------------------------------------------------------------------
# sub errors( this )
#
# Outputs kernel errors
#
# Parameters:
#   this  message object
#------------------------------------------------------------------------------

sub errors( $ )
{
  my ($self) = @_;
  my @message;
  my @table;
  my $rv = 0;

  use Sort::Naturally;

  my $alerts = get_log( $self );

  if (keys %{ $$alerts{SYNflood} })
  {
    $self->add_title( $Lang::tr{'statusmail kernel SYN flood'} );
    push @table, [ $Lang::tr{'interface'}, $Lang::tr{'ip address'}, $Lang::tr{'count'} ];

    foreach my $interface (sort {ncmp( $a, $b )} keys %{ $$alerts{SYNflood} })
    {
      foreach my $source (sort {ncmp( $a, $b ) } keys %{ $$alerts{SYNflood}{$interface} })
      {
        push @table, [ $interface, $source, $$alerts{SYNflood}{$interface}{$source} ];
      }
    }

    $self->add_table( @table );
    @table = ();

    $rv = 1;
  }

  if (keys %{ $$alerts{RAIDErrors} })
  {
    $self->add_title( $Lang::tr{'statusmail kernel raid errors'} );
    push @table, [ $Lang::tr{'statusmail error'}, $Lang::tr{'count'} ];

    foreach my $error ( sort {$$alerts{RAIDErrors}{$b} <=> $$alerts{RAIDErrors}{$a}} keys %{ $$alerts{RAIDErrors} } )
    {
      push @table, [ $error, $$alerts{RAIDErrors}{$error} ];
    }

    $self->add_table( @table );
    @table = ();

    $rv = 1;
  }

  if (keys %{ $$alerts{SegFaults} })
  {
    $self->add_title( $Lang::tr{'statusmail kernel segmentation fault'} );
    push @table, [ $Lang::tr{'statusmail executable'}, $Lang::tr{'count'} ];

    foreach my $executable ( sort {$$alerts{SegFaults}{$b} <=> $$alerts{SegFaults}{$a}} keys %{ $$alerts{SegFaults} } )
    {
      push @table, [ $executable, $$alerts{SegFaults}{$executable} ];
    }

    $self->add_table( @table );
    @table = ();

    $rv = 1;
  }

  if (keys %{ $$alerts{GPFaults} })
  {
    $self->add_title( $Lang::tr{'statusmail kernel general protection fault'} );
    push @table, [ $Lang::tr{'statusmail executable'}, $Lang::tr{'count'} ];

    foreach my $executable ( sort {$$alerts{GPFaults}{$b} <=> $$alerts{GPFaults}{$a}} keys %{ $$alerts{GPFaults} } )
    {
      push @table, [ $executable, $$alerts{GPFaults}{$executable} ];
    }

    $self->add_table( @table );
    @table = ();

    $rv = 1;
  }

  if (keys %{ $$alerts{TrapInt3s} })
  {
    $self->add_title( $Lang::tr{'statusmail kernel trap int3'} );
    push @table, [ $Lang::tr{'statusmail executable'}, $Lang::tr{'count'} ];

    foreach my $executable ( sort {$$alerts{TrapInt3s}{$b} <=> $$alerts{TrapInt3s}{$a}} keys %{ $$alerts{TrapInt3s} } )
    {
      push @table, [ $executable, $$alerts{TrapInt3s}{$executable} ];
    }

    $self->add_table( @table );
    @table = ();

    $rv = 1;
  }

  if (keys %{ $$alerts{UnalignedErrors} })
  {
    $self->add_title( $Lang::tr{'statusmail kernel unaligned'} );
    push @table, [ $Lang::tr{'statusmail executable'}, $Lang::tr{'count'} ];

    foreach my $executable ( sort {$$alerts{UnalignedErrors}{$b} <=> $$alerts{UnalignedErrors}{$a}} keys %{ $$alerts{UnalignedErrors} } )
    {
      push @table, [ $executable, $$alerts{UnalignedErrors}{$executable} ];
    }

    $self->add_table( @table );
    @table = ();

    $rv = 1;
  }

  if (keys %{ $$alerts{FPAssists} })
  {
    $self->add_title( $Lang::tr{'statusmail kernel FP Assists'} );
    push @table, [ $Lang::tr{'statusmail executable'}, $Lang::tr{'count'} ];

    foreach my $executable ( sort {$$alerts{FPAssists}{$b} <=> $$alerts{FPAssists}{$a}} keys %{ $$alerts{FPAssists} } )
    {
      push @table, [ $executable, $$alerts{FPAssists}{$executable} ];
    }

    $self->add_table( @table );
    @table = ();

    $rv = 1;
  }

  if (keys %{ $$alerts{OOM} })
  {
    $self->add_title( $Lang::tr{'statusmail kernel out of memory'} );
    push @table, [ $Lang::tr{'statusmail executable'}, $Lang::tr{'count'} ];

    foreach my $executable ( sort { $$alerts{OOM}{$b} <=> $$alerts{OOM}{$a} } keys %{ $$alerts{OOM} } )
    {
      push @table, [ $executable, $$alerts{OOM}{$executable} ];
    }

    $self->add_table( @table );
    @table = ();

    $rv = 1;
  }

  if (keys %{ $$alerts{Errors} })
  {
    $self->add_title( $Lang::tr{'statusmail kernel errors'} );
    push @table, [ $Lang::tr{'statusmail error'}, $Lang::tr{'count'} ];

    foreach my $error ( sort {$$alerts{Errors}{$b} <=> $$alerts{Errors}{$a}} keys %{ $$alerts{Errors} } )
    {
      push @table, [ $error, $$alerts{Errors}{$error} ];
    }

    $self->add_table( @table );
    @table = ();

    $rv = 1;
  }

  if (keys %{ $$alerts{EDACs} })
  {
    $self->add_title( $Lang::tr{'statusmail kernel edac messages'} );
    push @table, [ $Lang::tr{'statusmail message'}, $Lang::tr{'count'} ];

    foreach my $message ( sort {$$alerts{EDACs}{$b} <=> $$alerts{EDACs}{$a}} keys %{ $$alerts{EDACs} } )
    {
      push @table, [ $message, $$alerts{EDACs}{$message} ];
    }

    $self->add_table( @table );
    @table = ();

    $rv = 1;
  }

  return $rv;
}

1;
