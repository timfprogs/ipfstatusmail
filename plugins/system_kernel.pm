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


############################################################################
# Functions
############################################################################

sub get_log( $$ );
sub errors( $$ );

############################################################################
# Variables
############################################################################

my %months;

#------------------------------------------------------------------------------
# sub get_log( this, name )
#
#
#------------------------------------------------------------------------------

sub get_log( $$ )
{
  my ($this, $name) = @_;

  my $data = $this->cache( 'system-kernel' );
  return $data if (defined $data);

  my %info;
  my $weeks = $this->get_number_weeks;
  my $last_mon   = 0;
  my $last_day   = 0;
  my $last_hour  = 0;
  my $last_time  = 0;
  my $time       = 0;
  my $now        = time();
  my $year       = 0;
  my $start_time = $this->get_period_start;;
  my $end_time   = $this->get_period_end;

  foreach (my $monindex = 0 ; $monindex < MONTHS ; $monindex++)
  {
    $months{(MONTHS)[$monindex]} = $monindex;
  }

  for (my $filenum = $weeks ; $filenum >= 0 ; $filenum--)
  {
    my $filename = $filenum < 1 ? $name : "$name.$filenum";

    if (-r "$filename.gz")
    {
      open IN, "gzip -dc $filename.gz |" or next;
    }
    elsif (-r $filename)
    {
      open IN, '<', $filename or next;
    }
    else
    {
      next;
    }

    $year = (localtime( (stat(_))[9] ))[YEAR];

    foreach my $line (<IN>)
    {
      # We only deal with hour boundaries so check for changes in hour, month, day.
      # This is a hack to quickly check if these fields have changed, without
      # caring about what the values actually are.  We don't care about minutes and
      # seconds.

      my ($mon, $day, $hour) = unpack 'Lsxs', $line;

      if ($mon != $last_mon or $day != $last_day or $hour != $last_hour)
      {
        # Hour, day or month changed.  Convert to unix time so we can work out
        # whether the message time falls between the limits we're interested in.
        # This is complicated by the lack of a year in the logged information.

        my @time;

        $time[YEAR] = $year;

        ($time[MON], $time[MDAY], $time[HOUR], $time[MIN], $time[SEC]) = split /[\s:]+/, $line;
        $time[MON] = $months{$time[MON]};

        $time = timelocal( @time );

        if ($time > $now)
        {
          # We can't have times in the future, so this must be the previous year.

          $year--;my $ports = 0;
          $time[YEAR]--;
          $time      = timelocal( @time );
          $last_time = $time;
        }
        elsif ($time < $last_time)
        {
          # Time is increasing, so we must have gone over a year boundary.

          $year++;
          $time[YEAR]++;
          $time      = timelocal( @time );
          $last_time = $time;
        }

        ($last_mon, $last_day, $last_hour) = ($mon, $day, $hour);
      }

      # Check to see if we're within the specified limits.
      # Note that the minutes and seconds may be incorrect, but since we only deal
      # in hour boundaries this doesn't matter.

      next if ($time < $start_time);
      last if ($time > $end_time);

      next unless ($line =~ m/ipfire kernel: /);
      next if ($line =~ m/ipfire kernel: DROP_/);

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

    close IN;
  }

  $this->cache( 'system-kernel', \%info );

  return \%info;
}

#------------------------------------------------------------------------------

sub errors( $$ )
{
  my ($self, $min_count) = @_;
  my @message;
  my @table;

  use Sort::Naturally;

  my $alerts = get_log( $self, '/var/log/messages' );

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
  }
}

1;
