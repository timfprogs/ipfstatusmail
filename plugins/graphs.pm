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
use warnings;

require "${General::swroot}/lang.pl";
require "${General::swroot}/graphs.pl";

package Graphs;

############################################################################
# Function prototypes
############################################################################

sub add_graph( $$$$@ );

############################################################################
# BEGIN Block
#
# Register the graphs available in this file.
#
# Note that some graphs are only available under certain circumstances, so
# it's necessary to check the circumstances apply.
############################################################################

sub BEGIN
{
  my %netsettings;
  my %mainsettings;

  &General::readhash("${General::swroot}/ethernet/settings", \%netsettings);
  &General::readhash("${General::swroot}/main/settings", \%mainsettings);

  my $config_type = $netsettings{'CONFIG_TYPE'};

  my %common_options = ( 'section'    => $Lang::tr{'graph'},
                         'format'     => 'html' );

  #----------------------------------------------------------------------------
  # Network

  if ($netsettings{'RED_TYPE'} ne 'PPPOE')
  {
    if ($netsettings{'RED_DEV'} ne $netsettings{'GREEN_DEV'})
    {
      if ($netsettings{'RED_DEV'} eq 'red0')
      {
        main::add_mail_item( %common_options,
                            'ident'       => 'graph-network-red0',
                            'subsection'  => $Lang::tr{'interfaces'},
                            'item'        => 'red0',
                            'function'    => \&red0 );
      }
      else
      {
        main::add_mail_item( %common_options,
                            'ident'       => 'graph-network-ppp0',
                            'subsection'  => $Lang::tr{'interfaces'},
                            'item'        => 'ppp0',
                            'function'    => \&ppp0 );
      }
    }
  }
  else
  {
    main::add_mail_item( %common_options,
                        'ident'       => 'graph-network-ppp0',
                        'subsection'  => $Lang::tr{'interfaces'},
                        'item'        => 'ppp0',
                        'function'    => \&ppp0 );
  }

  main::add_mail_item( %common_options,
                       'ident'       => 'graph-network-green0',
                       'subsection'  => $Lang::tr{'interfaces'},
                       'item'        => 'green0',
                       'function'    => \&green0 );

  if ($config_type == 3 or $config_type == 4)
  {
    # BLUE
    main::add_mail_item( %common_options,
                         'ident'       => 'graph-network-blue0',
                         'subsection'  => $Lang::tr{'interfaces'},
                         'item'        => 'blue0',
                         'function'    => \&blue0 );
  }

  if ($config_type == 2 or $config_type == 4)
  {
    # ORANGE
    main::add_mail_item( %common_options,
                         'ident'       => 'graph-network-orange0',
                         'subsection'  => $Lang::tr{'interfaces'},
                         'item'        => 'orange0',
                         'function'    => \&orange0 );
  }


  if (-e "/var/log/rrd/collectd/localhost/interface/if_octets-ipsec0.rrd")
  {
    main::add_mail_item( %common_options,
                         'ident'       => 'graph-network-ipsec0',
                         'subsection'  => $Lang::tr{'network'},
                         'item'        => 'ipsec0',
                         'function'    => \&ipsec0 );
  }

  if (-e "/var/log/rrd/collectd/localhost/interface/if_octets-tun0.rrd")
  {
    main::add_mail_item( %common_options,
                         'ident'       => 'graph-network-tun0',
                         'subsection'  => $Lang::tr{'network'},
                         'item'        => 'tun0',
                         'function'    => \&tun0 );
  }

  main::add_mail_item( %common_options,
                       'ident'       => 'graph-network-fwhits',
                       'subsection'  => $Lang::tr{'network'},
                       'item'        => $Lang::tr{'firewallhits'},
                       'function'    => \&fw_hits );

  #----------------------------------------------------------------------------
  # System

  main::add_mail_item( %common_options,
                       'ident'       => 'graph-system-cpu-usage',
                       'subsection'  => $Lang::tr{'system'},
                       'item'        => "CPU $Lang::tr{'graph'}",
                       'function'    => \&cpu_usage );

  main::add_mail_item( %common_options,
                       'ident'       => 'graph-system-cpu-load',
                       'subsection'  => $Lang::tr{'system'},
                       'item'        => "Load $Lang::tr{'graph'}",
                       'function'    => \&cpu_load );

  if ( -e "$mainsettings{'RRDLOG'}/collectd/localhost/cpufreq/cpufreq-0.rrd")
  {
    main::add_mail_item( %common_options,
                         'ident'       => 'graph-system-cpu-frequency',
                         'subsection'  => $Lang::tr{'system'},
                         'item'        => "CPU $Lang::tr{'frequency'}",
                         'function'    => \&cpu_freq );
  }

  main::add_mail_item( %common_options,
                       'ident'       => 'graph-system-entropy',
                       'subsection'  => $Lang::tr{'system'},
                       'item'        => $Lang::tr{'entropy'},
                       'function'    => \&entropy );

  #----------------------------------------------------------------------------
  # Hardware

  main::add_mail_item( %common_options,
                       'ident'       => 'graph-hardware-cpu-load',
                       'subsection'  => $Lang::tr{'hardware graphs'},
                       'item'        => "Load $Lang::tr{'graph'}",
                       'function'    => \&cpu_load );

  if ( `ls $mainsettings{'RRDLOG'}/collectd/localhost/thermal-thermal_zone* 2>/dev/null` )
  {
    main::add_mail_item( %common_options,
                         'ident'       => 'graph-hardware-acpi-zone-temp',
                         'subsection'  => $Lang::tr{'hardware graphs'},
                         'item'        => "ACPI Thermal-Zone Temp",
                         'function'    => \&therm );
  }

  if ( `ls $mainsettings{'RRDLOG'}/collectd/localhost/sensors-*/temperature-* 2>/dev/null` )
  {
    main::add_mail_item( %common_options,
                         'ident'       => 'graph-hardware-temp',
                         'subsection'  => $Lang::tr{'hardware graphs'},
                         'item'        => "hwtemp",
                         'function'    => \&hwtemp );
  }

  if ( `ls $mainsettings{'RRDLOG'}/collectd/localhost/sensors-*/fanspeed-* 2>/dev/null` )
  {
    main::add_mail_item( %common_options,
                         'ident'       => 'graph-hardware-fan',
                         'subsection'  => $Lang::tr{'hardware graphs'},
                         'item'        => "hwfan",
                         'function'    => \&hwfan );
  }

  if ( `ls $mainsettings{'RRDLOG'}/collectd/localhost/sensors-*/voltage-* 2>/dev/null` )
  {
    main::add_mail_item( %common_options,
                         'ident'       => 'graph-hardware-volt',
                         'subsection'  => $Lang::tr{'hardware graphs'},
                         'item'        => "hwvolt",
                         'function'    => \&hwvolt );
  }

  # Memory

  main::add_mail_item( %common_options,
                      'ident'       => 'graph-memory-memory',
                      'subsection'  => $Lang::tr{'memory'},
                      'item'        => $Lang::tr{'memory'},
                      'function'    => \&memory );

  main::add_mail_item( %common_options,
                       'ident'       => 'graph-memory-swap',
                       'subsection'  => $Lang::tr{'memory'},
                       'item'        => $Lang::tr{'swap'},
                       'function'    => \&swap );

  #----------------------------------------------------------------------------
  # Disks

  foreach my $path (glob '/var/log/rrd/collectd/localhost/disk*')
  {
    my ($name) = $path =~ m/disk\-(\w+)/;

    main::add_mail_item( %common_options,
                         'ident'       => "graph-disk-access-$name",
                         'subsection'  => $Lang::tr{'statusmail disk access'},
                         'item'        => $name,
                         'function'    => sub { my ($this, $dummy) = @_; diskaccess( $this, $name ); } );

    main::add_mail_item( %common_options,
                         'ident'       => "graph-disk-temp-$name",
                         'subsection'  => $Lang::tr{'statusmail disk temperature'},
                         'item'        => $name,
                         'function'    => sub { my ($this, $dummy) = @_; disktemp( $this, $name ); } );
  }

# Other graphs that aren't available.
# 	updatepinggraph( host, period )                                     : netother.cgi
# 	updateprocessescpugraph( period )
# 	updateprocessesmemorygraph( period )
# 	updateqosgraph( device, period )        red0 | ppp0 | imq0          : qos.cgi
# 	updatevpngraph( interface, period )                                 : netovpnrw.cgi
# 	updatevpnn2ngraph( interface, period )                              : netovpnsrv.cgi
# 	updatewirelessgraph( interface, period )

}

############################################################################
# Code
############################################################################

sub calc_period( $ )
{
  my ($this) = @_;
  my $period;

  if ($this->{total_days} <= 0.05)
  {
    $period = 'hour';
  }
  elsif ($this->{total_days} <= 1)
  {
    $period = 'day';
  }
  elsif ($this->{total_days} <= 7)
  {
    $period = 'week'
  }
  elsif ($this->{total_days} <= 30)
  {
    $period = 'month'
  }
  else
  {
    $period = 'year';
  }

  return $period;
}


#------------------------------------------------------------------------------
# sub add_graph( object, interface, period )
#------------------------------------------------------------------------------

sub add_graph( $$$$@ )
{
  my ($this, $function, $name, $alternate, @params) = @_;

  my $from_child;

  push @params, calc_period( $this );

  my $pid = open( $from_child, "-|" );

  if ($pid)
  {   # parent
    binmode $from_child;

    $this->add_image( fh   => $from_child,
                      alt  => $alternate,
                      # The main Graphs lib generates SVGs.
                      type => 'image/svg+xml',
                      name => $name );

    waitpid( $pid, 0 );
    close $from_child;
  }
  else
  {      # child
    binmode( STDOUT );

    &$function( @params );

    exit;
  }
}


#------------------------------------------------------------------------------
# sub ppp0
#
# Adds a graph of the ppp0 interface
#------------------------------------------------------------------------------

sub ppp0( $$$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'ppp0_if.svg', 'ppp0 interface throughput', 'ppp0' );

  return 1;
}


#------------------------------------------------------------------------------
# sub red0
#
# Adds a graph of the red0 interface
#------------------------------------------------------------------------------

sub red0( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'red0_if.svg', 'red0 interface throughput', 'red0' );

  return 1;
}


#------------------------------------------------------------------------------
# sub green0
#
# Adds a graph of the ppp0 interface
#------------------------------------------------------------------------------

sub green0( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'green0_if.svg', 'green0 interface throughput', 'green0' );

  return 1;
}


#------------------------------------------------------------------------------
# sub blue0
#
# Adds a graph of the blue0 interface
#------------------------------------------------------------------------------

sub blue0( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'blue0_if.svg', 'blue0 interface throughput', 'blue0' );

  return 1;
}


#------------------------------------------------------------------------------
# sub orange0
#
# Adds a graph of the orange0 interface
#------------------------------------------------------------------------------

sub orange0( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'orange0_if.svg', 'orange0 interface throughput', 'orange0' );

  return 1;
}


#------------------------------------------------------------------------------
# sub ipsec0
#
# Adds a graph of the ipsec0 interface
#------------------------------------------------------------------------------

sub ipsec0( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'ipsec0_if.svg', 'ipsec0 interface throughput', 'ipsec0' );

  return 1;
}


#------------------------------------------------------------------------------
# sub tun0
#
# Adds a graph of the tun0 interface
#------------------------------------------------------------------------------

sub tun0( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'tun0_if.svg', 'tun0 interface throughput', 'tun0' );

  return 1;
}


#------------------------------------------------------------------------------
# sub cpu_usage
#
# Adds a graph of the CPU usage
#------------------------------------------------------------------------------

sub cpu_usage( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updatecpugraph, 'cpu_usage.svg', "CPU $Lang::tr{'graph'}" );

  return 1;
}


#------------------------------------------------------------------------------
# sub cpu_freq( $$ )
#
# Adds a graph of the CPU frequency
#------------------------------------------------------------------------------

sub cpu_freq( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updatecpufreqgraph, 'cpu_freq.svg', "CPU $Lang::tr{'frequency'}" );

  return 1;
}


#------------------------------------------------------------------------------
# sub cpu_load( $$ )
#
# Adds a graph of the CPU load
#------------------------------------------------------------------------------

sub cpu_load( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updateloadgraph,, 'cpu_load.svg', "Load $Lang::tr{'graph'}" );

  return 1;
}


#------------------------------------------------------------------------------
# sub fw_hits( $$ )
#
# Adds a graph of the Firewall hits
#------------------------------------------------------------------------------

sub fw_hits( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updatefwhitsgraph, 'fw_hits.svg', $Lang::tr{'firewallhits'} );

  return 1;
}


#------------------------------------------------------------------------------
# sub therm( $$ )
#
# Adds a graph of the ACPI Thermal zone temperatures
#------------------------------------------------------------------------------

sub therm( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updatethermaltempgraph, 'therm.svg', "ACPI Thermal-Zone Temp" );

  return 1;
}


#------------------------------------------------------------------------------
# sub hwtemp( $$ )
#
# Adds a graph of the Hardware Temperatures
#------------------------------------------------------------------------------

sub hwtemp( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updatehwtempgraph, 'hw_temp.svg', 'hwtemp' );

  return 1;
}


#------------------------------------------------------------------------------
# sub hwfan( $$ )
#
# Adds a graph of the Fan Speeds
#------------------------------------------------------------------------------

sub hwfan( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updatehwfangraph, 'hw_fan.svg', 'hwfan' );

  return 1;
}


#------------------------------------------------------------------------------
# sub hwvolt( $$ )
#
# Adds a graph of the Hardware voltages
#------------------------------------------------------------------------------

sub hwvolt( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updatehwvoltgraph, 'hw_volt.svg', 'hw volt' );

  return 1;
}


#------------------------------------------------------------------------------
# sub entropy( $$ )
#
# Adds a graph of the Entropy
#------------------------------------------------------------------------------

sub entropy( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updateentropygraph, 'entropy.svg', $Lang::tr{'entropy'} );

  return 1;
}


#------------------------------------------------------------------------------
# sub memory( $$ )
#
# Adds a graph of the memory usage
#------------------------------------------------------------------------------

sub memory( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updatememorygraph, 'memory.svg', $Lang::tr{'memory'} );

  return 1;
}


#------------------------------------------------------------------------------
# sub swap( $$ )
#
# Adds a graph of the swapfile usage
#------------------------------------------------------------------------------

sub swap( $$ )
{
  my ($this, $dummy) = @_;

  add_graph( $this, \&Graphs::updateswapgraph, 'swap.svg', $Lang::tr{'swap'} );

  return 1;
}


#------------------------------------------------------------------------------
# sub diskaccess( $$ )
#
# Adds a graph of the disk access rate
#------------------------------------------------------------------------------

sub diskaccess( $$ )
{
  my ($this, $name) = @_;

  add_graph( $this, \&Graphs::updatediskgraph, "disk_access_$name.svg", $name, $name );

  return 1;
}


#------------------------------------------------------------------------------
# sub updatehddgraph( $$ )
#
# Adds a graph of the disk temperature
#------------------------------------------------------------------------------

sub disktemp( $$ )
{
  my ($this, $name) = @_;

  add_graph( $this, \&Graphs::updatehddgraph, "disk_temp_$name.svg", $name, $name );

  return 1;
}

1;
