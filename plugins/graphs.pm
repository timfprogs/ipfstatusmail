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
require "${General::swroot}/graphs.pl";

package Graphs;

############################################################################
# Function prototypes
############################################################################

sub add_graph( $$$$$$ );

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  my %netsettings;
  my %mainsettings;

  &General::readhash("${General::swroot}/ethernet/settings", \%netsettings);
  &General::readhash("${General::swroot}/main/settings", \%mainsettings);

  my $config_type = $netsettings{'CONFIG_TYPE'};

  my %common_options = ( 'section'    => $Lang::tr{'graph'},
                         'format'     => 'html',
                         'option'     => { 'type'   => 'select',
                                           'name'   => $Lang::tr{'statusmail period'},
                                           'values' => [ "$Lang::tr{'hour'}:hour",
                                                         "$Lang::tr{'day'}:day",
                                                         "$Lang::tr{'week'}:week",
                                                         "$Lang::tr{'year'}:year" ] } );

  # Network

  if ($netsettings{'RED_TYPE'} ne 'PPPOE')
  {
    if ($netsettings{'RED_DEV'} ne $netsettings{'GREEN_DEV'})
    {
      if ($netsettings{'RED_DEV'} eq 'red0')
      {
        main::add_mail_item( %common_options,
                            'ident'       => 'graph-network-red0',
                            'subsection'  => $Lang::tr{'network'},
                            'item'        => $Lang::tr{'red'},
                            'function'    => \&red0 );
      }
      else
      {
        main::add_mail_item( %common_options,
                            'ident'       => 'graph-network-ppp0',
                            'subsection'  => $Lang::tr{'network'},
                            'item'        => $Lang::tr{'red'},
                            'function'    => \&ppp0 );
      }
    }
  }
  else
  {
    main::add_mail_item( %common_options,
                        'ident'       => 'graph-network-ppp0',
                        'subsection'  => $Lang::tr{'network'},
                        'item'        => $Lang::tr{'red'},
                        'function'    => \&ppp0 );
  }

  main::add_mail_item( %common_options,
                       'ident'       => 'graph-network-green0',
                       'subsection'  => $Lang::tr{'network'},
                       'item'        => $Lang::tr{'green'},
                       'function'    => \&green0 );

  if ($config_type == 3 or $config_type == 4)
  {
    # BLUE
    main::add_mail_item( %common_options,
                         'ident'       => 'graph-network-blue0',
                         'subsection'  => $Lang::tr{'network'},
                         'item'        => $Lang::tr{'blue'},
                         'function'    => \&blue0 );
  }

  if ($config_type == 2 or $config_type == 4)
  {
    # ORANGE
    main::add_mail_item( %common_options,
                         'ident'       => 'graph-network-orange0',
                         'subsection'  => $Lang::tr{'network'},
                         'item'        => $Lang::tr{'orange'},
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

# 	updatediskgraph( disk, period )
# 	updatehddgraph( disk, period )          sd? - temperature
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

#------------------------------------------------------------------------------
# sub add_graph( object, interface, period )
#------------------------------------------------------------------------------

sub add_graph( $$$$$$ )
{
  my ($this, $function, $param, $period, $name, $alternate) = @_;

  my $from_child;

  my $pid = open( $from_child, "-|" );

  if ($pid)
  {   # parent
    binmode $from_child;

    $this->add_image( fh   => $from_child,
                      alt  => $alternate,
                      type => 'image/png',
                      name => $name );

    waitpid( $pid, 0 );
    close $from_child;
  }
  else
  {      # child
    binmode( STDOUT );

    if (defined $param)
    {
      &$function( $param, $period );
    }
    else
    {
      &$function( $period );
    }

    exit;
  }
}


#------------------------------------------------------------------------------
# sub ppp0
#
# Adds a graph of the ppp0 interface
#------------------------------------------------------------------------------

sub ppp0( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'ppp0', $period, 'ppp0_if.png', 'ppp0 interface throughput' );
}


#------------------------------------------------------------------------------
# sub red0
#
# Adds a graph of the red0 interface
#------------------------------------------------------------------------------

sub red0( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'red0', $period, 'red0_if.png', 'red0 interface throughput' );
}


#------------------------------------------------------------------------------
# sub green0
#
# Adds a graph of the ppp0 interface
#------------------------------------------------------------------------------

sub green0( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'green0', $period, 'green0_if.png', 'green0 interface throughput' );
}


#------------------------------------------------------------------------------
# sub blue0
#
# Adds a graph of the blue0 interface
#------------------------------------------------------------------------------

sub blue0( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'blue0', $period, 'blue0_if.png', 'blue0 interface throughput' );
}


#------------------------------------------------------------------------------
# sub orange0
#
# Adds a graph of the orange0 interface
#------------------------------------------------------------------------------

sub orange0( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'orange0', $period, 'orange0_if.png', 'orange0 interface throughput' );
}


#------------------------------------------------------------------------------
# sub ipsec0
#
# Adds a graph of the ipsec0 interface
#------------------------------------------------------------------------------

sub ipsec0( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'ipsec0', $period, 'ipsec0_if.png', 'ipsec0 interface throughput' );
}


#------------------------------------------------------------------------------
# sub tun0
#
# Adds a graph of the tun0 interface
#------------------------------------------------------------------------------

sub tun0( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updateifgraph, 'tun0', $period, 'tun0_if.png', 'tun0 interface throughput' );
}


#------------------------------------------------------------------------------
# sub cpu_usage
#
# Adds a graph of the CPU usage
#------------------------------------------------------------------------------

sub cpu_usage( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updatecpugraph, undef, $period, 'cpu_usage.png', "CPU $Lang::tr{'graph'}" );
}


#------------------------------------------------------------------------------
# sub cpu_freq( $$ )
#
# Adds a graph of the CPU frequency
#------------------------------------------------------------------------------

sub cpu_freq( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updatecpufreqgraph, undef, $period, 'cpu_freq.png', "CPU $Lang::tr{'frequency'}" );
}


#------------------------------------------------------------------------------
# sub cpu_load( $$ )
#
# Adds a graph of the CPU load
#------------------------------------------------------------------------------

sub cpu_load( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updateloadgraph, undef, $period, 'cpu_load.png', "Load $Lang::tr{'graph'}" );
}


#------------------------------------------------------------------------------
# sub fw_hits( $$ )
#
# Adds a graph of the Firewall hits
#------------------------------------------------------------------------------

sub fw_hits( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updatefwhitsgraph, undef, $period, 'fw_hits.png', $Lang::tr{'firewallhits'} );
}


#------------------------------------------------------------------------------
# sub therm( $$ )
#
# Adds a graph of the ACPI Thermal zone temperatures
#------------------------------------------------------------------------------

sub therm( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updatethermaltempgraph, undef, $period, 'therm.png', "ACPI Thermal-Zone Temp" );
}


#------------------------------------------------------------------------------
# sub hwtemp( $$ )
#
# Adds a graph of the Hardware Temperatures
#------------------------------------------------------------------------------

sub hwtemp( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updatehwtempgraph, undef, $period, 'hw_temp.png', 'hwtemp' );
}


#------------------------------------------------------------------------------
# sub hwfan( $$ )
#
# Adds a graph of the Fan Speeds
#------------------------------------------------------------------------------

sub hwfan( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updatehwfangraph, undef, $period, 'hw_fan.png', 'hwfan' );
}


#------------------------------------------------------------------------------
# sub hwvolt( $$ )
#
# Adds a graph of the Hardware voltages
#------------------------------------------------------------------------------

sub hwvolt( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updatehwvoltgraph, undef, $period, 'hw_volt.png', 'hw volt' );
}


#------------------------------------------------------------------------------
# sub entropy( $$ )
#
# Adds a graph of the Entropy
#------------------------------------------------------------------------------

sub entropy( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updateentropygraph, undef, $period, 'entropy.png', $Lang::tr{'entropy'} );
}


#------------------------------------------------------------------------------
# sub memory( $$ )
#
# Adds a graph of the memory usage
#------------------------------------------------------------------------------

sub memory( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updatememorygraph, undef, $period, 'memory.png', $Lang::tr{'memory'} );
}


#------------------------------------------------------------------------------
# sub swap( $$ )
#
# Adds a graph of the swapfile usage
#------------------------------------------------------------------------------

sub swap( $$ )
{
  my ($this, $period) = @_;

  add_graph( $this, \&Graphs::updateswapgraph, undef, $period, 'swap.png', $Lang::tr{'swap'} );
}
