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

package Update_Packfire;

############################################################################
# Function prototypes
############################################################################

sub core( $ );


############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'section'    => $Lang::tr{'statusmail update'},
                       'subsection' => 'Pakfire',
                       'item'       => $Lang::tr{'statusmail core'},
                       'function'   => \&core );

  main::add_mail_item( 'section'    => $Lang::tr{'statusmail update'},
                       'subsection' => 'Pakfire',
                       'item'       => $Lang::tr{'statusmail addon'},
                       'function'   => \&addon );
}

############################################################################
# Code
############################################################################

#------------------------------------------------------------------------------
# sub core
#
# Adds the current status of the system processes
#------------------------------------------------------------------------------

sub core( $ )
{
  my $message = shift;

  my $installed_file   = '/opt/pakfire/db/core/mine';
  my $update_list_file = '/opt/pakfire/db/lists/core-list.db';

  open IN, '<', $installed_file or die "Can't open current core version file: $!";

  my $current = <IN>;
  chomp $current;

  close IN;

  my $core_release;

  open IN, '<', $update_list_file or die "Can't open core update list file: $!";

  foreach my $line (<IN>)
  {
    next unless ($line =~ m/core_release/);

    eval $line;
  }

  close IN;

  return unless ($current ne $core_release);

  $message->add_title( $Lang::tr{'statusmail core update available'} );
  $message->add_text( "Release $current to $core_release\n" );
}

#------------------------------------------------------------------------------
# sub addon
#
# Adds the current status of the system processes
#------------------------------------------------------------------------------

sub addon( $ )
{
  my $message = shift;

  my $installed_dir    = '/opt/pakfire/db/installed';
  my $update_list_file = '/opt/pakfire/db/lists/packages_list.db';

  my $name    = '';
  my $version = '';
  my %paks    = ();

  # Read the installed versions

  opendir DIR, $installed_dir or die "Can't open installed package dir: $!";

  foreach my $file (readdir DIR)
  {
    open IN, '<', "$installed_dir/$file" or die "Can't open package file $file: $!";

    foreach my $line (<IN>)
    {
      if ($line =~ m/^Name:\s+(\w+)/)
      {
        $name = $1;
      }
      elsif ($line =~ m/^ProgVersion:\s+(.+)/)
      {
        $version = $1;
      }

      if ($name and $version)
      {
        $paks{$name} = $version;
        $name        = '';
        $version     = '';
      }
    }

    close IN;
  }

  closedir DIR;

  # Read the available versions

  my $output = '';

  open IN, '<', $update_list_file or die "Can't open package list file $update_list_file: $!";

  foreach my $line (<IN>)
  {
    my ($name, $version) = split ';', $line;

    if (exists $paks{$name} and $version ne $paks{$name})
    {
      $output .= "$name: from $paks{$name} to $version\n";
    }
  }

  close IN;

  return unless ($output);

  $message->add_title( $Lang::tr{'statusmail addon updates available'} );


  $message->add_text( $output );
}

1;
