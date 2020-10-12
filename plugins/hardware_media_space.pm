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

package Hardware_Media_Space;

############################################################################
# Function prototypes
############################################################################

sub space( $$$ );
sub inodes( $$$ );

############################################################################
# BEGIN Block
#
# Register the log items available in this file
############################################################################

sub BEGIN
{
  main::add_mail_item( 'ident'      => 'hardware-media-space',
                       'section'    => $Lang::tr{'statusmail hardware'},
                       'subsection' => $Lang::tr{'media'},
                       'item'       => $Lang::tr{'disk usage'},
                       'function'   => \&space,
                       'option'     => { 'type'   => 'integer',
                                         'name'   => $Lang::tr{'statusmail max free percent'},
                                         'min'    => 0,
                                         'max'    => 100 } );

  main::add_mail_item( 'ident'      => 'hardware-media-inodes',
                       'section'    => $Lang::tr{'statusmail hardware'},
                       'subsection' => $Lang::tr{'media'},
                       'item'       => 'inodes',
                       'function'   => \&inodes,
                       'option'     => { 'type'   => 'integer',
                                         'name'   => $Lang::tr{'statusmail max free percent'},
                                         'min'    => 0,
                                         'max'    => 100 } );
}

############################################################################
# Code
############################################################################

#------------------------------------------------------------------------------
# sub space( this, param, min_percent )
#
# Adds the disk usage in terms of space used.
#
# Parameters:
#   this         message object
#   min_percent  Only display information if this amount of space or less is
#                free
#------------------------------------------------------------------------------

sub space( $$$ )
{
  my $message     = shift;
  my $param       = shift;
  my $min_percent = 100 - shift;
  my @lines;

  # Get the process information

  foreach my $line (`df -BM`)
  {
    my @fields = split /\s+/, $line, 6;
    if ($fields[4] =~ m/\d+\%/)
    {
      my ($percent) = $fields[4] =~ m/(\d+)\%/;
      next if ($percent <= $min_percent);
    }
    push @lines, [ @fields ];
  }

  if (@lines > 1)
  {
    $message->add_table( @lines );

    return 1;
  }

  return 0;
}


#------------------------------------------------------------------------------
# sub inodes( this, param, min_percent )
#
# Adds the disk usage in terms of inodes used.
#
# Parameters:
#   this         message object
#   min_percent  Only display information if this number of inodes or less is
#                free
#------------------------------------------------------------------------------

sub inodes( $$$ )
{
  my $message     = shift;
  my $param       = shift;
  my $min_percent = 100 - shift;
  my @lines;

  # Get the process information

  foreach my $line (`df -i`)
  {
    my @fields = split /\s+/, $line, 6;

    next if ($fields[4] eq '-');

    if ($fields[4] =~ m/\d+\%/)
    {
      my ($percent) = $fields[4] =~ m/(\d+)\%/;
      next if ($percent <= $min_percent);
    }
    push @lines, [ @fields ];
  }

  if (@lines > 1)
  {
    $message->add_table( @lines );

    return 1;
  }

  return 0;
}

1;
