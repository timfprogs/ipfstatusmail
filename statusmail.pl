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
use warnings;

use Sys::Syslog qw(:standard :macros);

use lib "/usr/lib/statusmail";

require "/var/ipfire/general-functions.pl";
require "${General::swroot}/lang.pl";

use StatusMail;

############################################################################
# Configuration variables
#
# These variables give the locations of various files used by this script
############################################################################

my $lib_dir              = "/usr/lib/statusmail";
my $plugin_dir           = "$lib_dir/plugins";
my $stylesheet           = "$lib_dir/stylesheet.css";
my $mainsettings         = "${General::swroot}/main/settings";
my $mailsettings         = "${General::swroot}/dma/mail.conf";
my $contactsettings      = "${General::swroot}/statusmail/contact_settings";
my $schedulesettings     = "${General::swroot}/statusmail/schedule_settings";
my $debug                = 0;

############################################################################
# Function prototypes
############################################################################

# Used by plugins

sub add_mail_item( % );

# Local functions

sub send_email( $ );
sub execute_schedule( $$ );
sub abort( $ );
sub log_message( $$ );
sub debug( $$ );

############################################################################
# Variables
############################################################################

my %mainsettings  = ();
my %sections      = ();
my $contacts      = {};
my $schedules     = {};
my %mailsettings  = ();

############################################################################
# Main function
############################################################################

openlog( "statusmail", "nofatal", LOG_USER);
log_message LOG_INFO, "Starting log and status email processing";

# Check for existence of settings files

exit unless (-r $contactsettings);
exit unless (-e $mailsettings);
exit unless (-r $schedulesettings);

# Read settings

General::readhash($mailsettings, \%mailsettings);
General::readhash($mainsettings, \%mainsettings);

unless ($mailsettings{'USEMAIL'} eq 'on')
{
  log_message LOG_WARNING, "Email disabled";
  exit;
};

eval qx|/bin/cat $contactsettings| if (-r $contactsettings);
eval qx|/bin/cat $schedulesettings| if (-r $schedulesettings);

# Scan for plugins

opendir DIR, $plugin_dir or abort "Can't open Plug-in directory $plugin_dir: $!";

foreach my $file (readdir DIR)
{
  next unless ($file =~ m/\.pm$/);

  debug 1, "Initialising plugin $file";

  require "$plugin_dir/$file";
}

# Check command line parameters

if (@ARGV)
{
  # Command line parameters provided - try to execute the named schedule.

  my ($schedule) = $ARGV[0];

  if (exists $$schedules{$schedule})
  {
    execute_schedule( $schedule, $$schedules{$schedule} );
  }
  else
  {
    print "Schedule '$schedule' not found\n";
  }

  closelog;
  exit;
}

# Look for a due schedule

my (undef, undef, $hour, $mday, undef, undef, $wday, undef, undef) = localtime;

$hour = 1 << $hour;
$wday = 1 << $wday;
$mday = 1 << $mday;

foreach my $schedule (keys %$schedules)
{
  next unless ($$schedules{$schedule}{'enable'} eq 'on'); # Must be enabled

  next unless ($$schedules{$schedule}{'mday'} & $mday or  # Must be due today
               $$schedules{$schedule}{'wday'} & $wday);

  next unless ($$schedules{$schedule}{'hours'} & $hour);  # Must be due this hour

  debug 1, "Schedule $schedule due";

  execute_schedule( $schedule, $$schedules{$schedule} );
}

closelog;

exit;

#------------------------------------------------------------------------------
# sub execute_schedule( name, schedule )
#
# Executes the specified schedule as long as at least one of the contacts is
# enabled.
#
# Parameters:
#   name      name of Schedule
#   schedule  reference of Schedule hash to be executed
#------------------------------------------------------------------------------

sub execute_schedule( $$ )
{
  my ($name, $schedule) = @_;
  my @contacts;
  my $status = 0;

  # Check that at least one of the contacts is enabled

  foreach my $contact (split '\|', $$schedule{'email'})
  {
    push @contacts, $contact if (exists $$contacts{$contact} and $$contacts{$contact}{'enable'} eq 'on');
  }

  if (not @contacts)
  {
    debug 1, "No enabled contacts";
    return;
  }

  log_message LOG_INFO, "Executing status mail schedule $name";

  # Look for a theme stylesheet

  my $theme_stylesheet = "$lib_dir/$mainsettings{'THEME'}.css";
  $stylesheet = $theme_stylesheet if (-r $theme_stylesheet);

  # Create message

  my $message = new StatusMail( 'format'             => $$schedule{'format'},
                                'subject'            => $$schedule{'subject'},
                                'to'                 => [ @contacts ],
                                'sender'             => $mailsettings{'SENDER'},
                                'max_lines_per_item' => $$schedule{'lines'},
                                'stylesheet'         => $stylesheet );

  if (not $message)
  {
    log_message LOG_WARNING, "Failed to create message object: $!";
    return;
  }

  $message->calculate_period( $$schedule{'period-value'}, $$schedule{'period-unit'} );

  $message->add_text( "$Lang::tr{'statusmail period from'} " . localtime( $message->get_period_start ) .
                      " $Lang::tr{'statusmail period to'} " . localtime( $message->get_period_end ) . "\n" );

  # Loop through the various log items

  foreach my $section ( sort keys %sections )
  {
    debug 3, "Section $section";
    $message->add_section( $section );

    foreach my $subsection ( sort keys %{ $sections{$section} } )
    {
      debug 3, "Subsection $subsection";
      $message->add_subsection( $subsection );

      foreach my $item ( sort keys %{ $sections{$section}{$subsection} } )
      {
        debug 3, "Item $item";

        # Is the item enabled?

        my $key = $sections{$section}{$subsection}{$item}{'ident'};

        next unless (exists $$schedule{"enable_$key"} and $$schedule{"enable_$key"} eq 'on');
        next unless ($sections{$section}{$subsection}{$item}{'format'} eq 'both' or
                     $sections{$section}{$subsection}{$item}{'format'} eq $$schedule{'format'});

        # Yes. Call the function to get it's content - with option if necessary

        debug 2, "Process item $section :: $subsection :: $item";

        $message->add_title( $item );

        my $function = $sections{$section}{$subsection}{$item}{'function'};

        if (exists $$schedule{"value_$key"})
        {
          $status += &$function( $message, $$schedule{"value_$key"} );
        }
        else
        {
          $status += &$function( $message );
        }
      }

      $message->clear_cache;
    }
  }

  # End the Message

  if ($status > 0)
  {
    debug 1, "Send mail message";
    $message->send;
  }
}


#------------------------------------------------------------------------------
# sub add_mail_item( params )
#
# Adds a possible status item to the section and subsection specified.  This
# function is called from the BEGIN block of the plugin.
#
# Any errors cause the item to be ignored without raising an error.
#
# Parameters:
#   params  hash containing details of the item to be added:
#     section     name of the section containing this item
#     subsection  name of the subsection containing this item
#     item        name of the item
#     function    function called to add item to message
#     format      available formats for the item 'html', 'text' or 'both'
#     option      hash specifying option parameter (optional)
#
# option can specify either a selection or an integer.  For a selection it
# contains:
#   type          must be 'option'
#   values        array of strings representing the possible options
#
# For an integer option contains:
#   type          must be 'integer'
#   min           minimum valid value of parameter
#   max           maximum valid value of parameter
#------------------------------------------------------------------------------

sub add_mail_item( % )
{
  my %params = @_;

  # Check for all required parameters

  return unless (exists $params{'section'}    and
                 exists $params{'subsection'} and
                 exists $params{'item'}       and
                 exists $params{'function'} );

  # Check the option

  if ($params{'option'})
  {
    return unless (ref $params{'option'} eq 'HASH');

    if ($params{'option'}{'type'} eq 'select')
    {
      return unless (ref $params{'option'}{'values'} eq 'ARRAY' and @{ $params{'option'}{'values'} } > 1);
    }
    elsif ($params{'option'}{'type'} eq 'integer')
    {
      return unless (exists $params{'option'}{'min'} and exists $params{'option'}{'max'} and $params{'option'}{'min'} < $params{'option'}{'max'});
    }
    else
    {
      return;
    }
  }

  $params{'format'} = 'both' unless (exists $params{'format'});

  # Record that the option exists

  $sections{$params{'section'}}{$params{'subsection'}}{$params{'item'}} = { 'function' => $params{'function'},
                                                                            'format'   => $params{'format'},
                                                                            'ident'    => $params{'ident'} };
}


#------------------------------------------------------------------------------
# sub abort( message )
#
# Aborts the update run, printing out an error message.
#
# Parameters:
#   message     Message to be printed
#------------------------------------------------------------------------------

sub abort( $ )
{
my ($message) = @_;

  log_message( LOG_ERR, $message );
  croak $message;
}


#------------------------------------------------------------------------------
# sub log_message( level, message )
#
# Logs a message to the system log.  If the script is run from the terminal
# then the message is also printed locally.
#
# Parameters:
#   level   Severity of message
#   message Message to be logged
#------------------------------------------------------------------------------

sub log_message( $$ )
{
  my ($level, $message) = @_;

  print "($level) $message\n" if (-t STDIN);
  syslog( $level, $message );
}


#------------------------------------------------------------------------------
# sub debug( level, message )
#
# Optionally logs a debug message
#
# Parameters:
#   level   Debug level
#   message Message to be logged
#------------------------------------------------------------------------------

sub debug( $$ )
{
  my ($level, $message) = @_;

  if (($level <= $debug) or
      ($level == 1 and -t STDIN))
  {
    log_message LOG_DEBUG, $message;
  }
}
