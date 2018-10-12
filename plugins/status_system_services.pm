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

package Status_System_Services;


############################################################################
# Function prototypes
############################################################################

sub services( $ );
sub isrunning( $$ );
sub isrunningaddon( $$ );

############################################################################
# Function prototypes
############################################################################

my %netsettings=();
my $read_netsettings = 0;

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'ident'      => 'system-status-services',
                       'section'    => $Lang::tr{'system'},
                       'subsection' => $Lang::tr{'status'},
                       'item'       => $Lang::tr{'services'},
                       'function'   => \&services );
}

############################################################################
# Code
############################################################################

#------------------------------------------------------------------------------
# sub services
#
# Adds the current status of the system services
#------------------------------------------------------------------------------

sub services( $ )
{
  my $message = shift;

  my @output;

  if (not $read_netsettings)
  {
    &General::readhash("${General::swroot}/ethernet/settings", \%netsettings);
    $read_netsettings = 1;
  }

  my %servicenames = (
      $Lang::tr{'dhcp server'} => 'dhcpd',
      $Lang::tr{'web server'} => 'httpd',
      $Lang::tr{'cron server'} => 'fcron',
      $Lang::tr{'dns proxy server'} => 'unbound',
      $Lang::tr{'logging server'} => 'syslogd',
      $Lang::tr{'kernel logging server'} => 'klogd',
      $Lang::tr{'ntp server'} => 'ntpd',
      $Lang::tr{'secure shell server'} => 'sshd',
      $Lang::tr{'vpn'} => 'charon',
      $Lang::tr{'web proxy'} => 'squid',
      'OpenVPN' => 'openvpn'
    );
 my %fullname = (
      $Lang::tr{'dhcp server'} => "$Lang::tr{'dhcp server'}",
      $Lang::tr{'web server'} => $Lang::tr{'web server'},
      $Lang::tr{'cron server'} => $Lang::tr{'cron server'},
      $Lang::tr{'dns proxy server'} => $Lang::tr{'dns proxy server'},
      $Lang::tr{'logging server'} => $Lang::tr{'logging server'},
      $Lang::tr{'kernel logging server'} => $Lang::tr{'kernel logging server'},
      $Lang::tr{'ntp server'} => "$Lang::tr{'ntp server'}",
      $Lang::tr{'secure shell server'} => "$Lang::tr{'secure shell server'}",
      $Lang::tr{'vpn'} => "$Lang::tr{'vpn'}",
      $Lang::tr{'web proxy'} => "$Lang::tr{'web proxy'}",
      'OpenVPN' => "OpenVPN",
      "$Lang::tr{'intrusion detection system'} (GREEN)" => "$Lang::tr{'intrusion detection system'} (GREEN)",
      "$Lang::tr{'intrusion detection system'} (RED)" => "$Lang::tr{'intrusion detection system'} (RED)",
      "$Lang::tr{'intrusion detection system'} (ORANGE)" => "$Lang::tr{'intrusion detection system'} (ORANGE)",
      "$Lang::tr{'intrusion detection system'} (BLUE)" => "$Lang::tr{'intrusion detection system'} (BLUE)"
    );

  my $iface = '';

  if (open(FILE, "${General::swroot}/red/iface"))
  {
    $iface = <FILE>;
    close FILE;
    chomp $iface;
  }

  $servicenames{"$Lang::tr{'intrusion detection system'} (RED)"}   = "snort_${iface}";
  $servicenames{"$Lang::tr{'intrusion detection system'} (GREEN)"} = "snort_$netsettings{'GREEN_DEV'}";

  if (exists $netsettings{'ORANGE_DEV'} and $netsettings{'ORANGE_DEV'} ne '')
  {
    $servicenames{"$Lang::tr{'intrusion detection system'} (ORANGE)"} = "snort_$netsettings{'ORANGE_DEV'}";
  }

  if (exists $netsettings{'BLUE_DEV'} and $netsettings{'BLUE_DEV'} ne '')
  {
    $servicenames{"$Lang::tr{'intrusion detection system'} (BLUE)"} = "snort_$netsettings{'BLUE_DEV'}";
  }

  $message->add_title( $Lang::tr{'services'} );

  if ($message->is_html)
  {
    push @output, "<table>\n";
    push @output, "<tr><th align='left'>$Lang::tr{'services'}</th><th>$Lang::tr{'status'}</th><th>PID</th><th>$Lang::tr{'memory'}</th></tr>\n";
  }
  else
  {
    push @output, [ $Lang::tr{'services'}, $Lang::tr{'status'}, 'PID', $Lang::tr{'memory'} ];
  }

  foreach my $key (sort keys %servicenames)
  {
    my $shortname = $servicenames{$key};
    my @status = isrunning( $message, $shortname );

    if ($message->is_html)
    {
      my $running = "<td class='ok'>$Lang::tr{'running'}</td>";

      if ($status[0] ne $Lang::tr{'running'})
      {
        $running = "<td class='error'>$Lang::tr{'stopped'}</td>";
      }

      push @output, "<tr><td>$key</td>$running<td style='text-align: right'>$status[1]</td><td style='text-align: right'>$status[2]</td></tr>\n";
    }
    else
    {
      push @output, [ $key, @status ];
    }
  }

  if ($message->is_html)
  {
    push @output,  "</table>\n";

    $message->add( @output );

    @output = ();

    $message->add_title( "Addon - $Lang::tr{'services'}" );
    push @output, "<table>\n";
    push @output,  "<tr><th align='left'>$Lang::tr{'services'}</th><th>$Lang::tr{'status'}</th><th>PID</th><th>$Lang::tr{'memory'}</th></tr>\n";
  }
  else
  {
    $message->add_table( @output );
    @output = ();

    $message->add_title( "Addon - $Lang::tr{'services'}" );

    push @output, [ $Lang::tr{'services'}, $Lang::tr{'status'}, '', $Lang::tr{'memory'} ];
  }

  my @pak = `find /opt/pakfire/db/installed/meta-* 2>/dev/null | cut -d"-" -f2`;

  foreach my $pak (@pak)
  {
    chomp($pak);

    # Check which of the paks are services
    my @services = `find /etc/init.d/$pak 2>/dev/null | cut -d"/" -f4`;

    foreach my $key (@services)
    {
      # blacklist some packages
      #
      # alsa has trouble with the volume saving and was not really stopped
      # mdadm should not stopped with webif because this could crash the system
      #
      chomp($key);

      next if ( $key eq 'squid' );

      if ( ($key ne "alsa") and ($key ne "mdadm") )
      {
        my $shortname = $servicenames{$key};
        my @status = isrunningaddon( $message, $key );

        if ($message->is_html)
        {
          my $running = "<td class='ok'>$Lang::tr{'running'}</td>";

          if ($status[0] ne $Lang::tr{'running'})
          {
            $running = "<td class='error'>$Lang::tr{'stopped'}</td>";
          }

          push @output, "<tr><td>$key</td>$running<td style='text-align: right'>$status[1]</td><td style='text-align: right'>$status[2]</td></tr>\n";
        }
        else
        {
          push @output, [ $key, @status ];
        }
      }
    }
  }

  push @output,  "</table>\n" if ($message->is_html);

  if ($message->is_html)
  {
    $message->add( @output );
  }
  else
  {
    $message->add_table( @output );
  }
}

sub isrunning( $$ )
{
  my ($message, $cmd) = @_;
  my @status;
  my $pid     = '';
  my $testcmd = '';
  my $exename;
  my $memory;

  @status = ( $Lang::tr{'stopped'}, '', '' );

  $cmd =~ /(^[a-z]+)/;
  $exename = $1;

  if (open(FILE, "/var/run/${cmd}.pid"))
  {
    $pid = <FILE>;
    chomp $pid;
    close FILE;

    if (open(FILE, "/proc/${pid}/status"))
    {
      while (<FILE>)
      {
        if (/^Name:\W+(.*)/)
        {
          $testcmd = $1;
        }
      }
      close FILE;
    }

    if (open(FILE, "/proc/${pid}/status"))
    {
      while (<FILE>)
      {
        my ($key, $val) = split(":", $_, 2);
        if ($key eq 'VmRSS')
        {
          $memory = $val;
          chomp $memory;
          last;
        }
      }
      close(FILE);
    }

    if ($testcmd =~ /$exename/)
    {
      @status = ( $Lang::tr{'running'}, $pid, $memory );
    }
  }

  return @status;
}



sub isrunningaddon( $$ )
{
  my ($message, $cmd) = @_;
  my @status;
  my $pid = '';
  my $exename;
  my @memory;

  @status = ( $Lang::tr{'stopped'}, '', '' );

  my $testcmd = `/usr/local/bin/addonctrl $cmd status 2>/dev/null`;

  if ( $testcmd =~ /is\ running/ && $testcmd !~ /is\ not\ running/)
  {
    @status = ( $Lang::tr{'running'} );

    $testcmd =~ s/.* //gi;
    $testcmd =~ s/[a-z_]//gi;
    $testcmd =~ s/\[[0-1]\;[0-9]+//gi;
    $testcmd =~ s/[\(\)\.]//gi;
    $testcmd =~ s/  //gi;
    $testcmd =~ s///gi;

    my @pid = split( /\s/, $testcmd );

    push @status, $pid[0];

    my $memory = 0;

    foreach (@pid)
    {
      chomp($_);
      if (open(FILE, "/proc/$_/statm"))
      {
        my $temp = <FILE>;
        @memory = split(/ /,$temp);
      }
      $memory += $memory[0];
    }

    push @status, "${memory} kB";
  }
  else
  {
    @status = ( $Lang::tr{'stopped'}, '', '' );
  }

  return @status;
}

1;
