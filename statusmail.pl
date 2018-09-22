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

use Sys::Syslog qw(:standard :macros);

use lib "/var/ipfire/statusmail";

require "/var/ipfire/general-functions.pl";
require "${General::swroot}/lang.pl";

use StatusMail;

############################################################################
# Configuration variables
#
# These variables give the locations of various files used by this script
############################################################################

my $plugin_dir           = "${General::swroot}/statusmail/plugins";
my $stylesheet           = "${General::swroot}/statusmail/stylesheet.css";
my $settings             = "$plugin_dir/settings";
my $main_settings        = "${General::swroot}/main/settings";
my $mailsettings         = "${General::swroot}/dma/mail.conf";
my $contacts             = "${General::swroot}/statusmail/contacts";
my $schedules            = "${General::swroot}/statusmail/schedules";
my $debug                = 9;

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
sub read_settings( $$ );

############################################################################
# Variables
############################################################################

my %main_settings = ();
my %sections      = ();
my %contacts      = ();
my %schedules     = ();
my %mailsettings  = ();


############################################################################
# Main function
############################################################################

openlog( "logmail", "nofatal", LOG_USER);
log_message LOG_INFO, "Starting log and status email processing";

# Check for existence of settings files

exit unless (-r $contacts);
exit unless (-e $mailsettings);
exit unless (-r $schedules);

# Read settings

General::readhash($mailsettings, \%mailsettings);

unless ($mailsettings{'USEMAIL'} eq 'on')
{
  log_message LOG_WARNING, "Email disabled";
  exit;
};

read_settings( $contacts, \%contacts );
read_settings( $schedules, \%schedules );

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

  if (not exists $schedules{$schedule})
  {
    print "Schedule '$schedule' not found\n";
    closelog;
    exit;
  }

  execute_schedule( $schedule, $schedules{$schedule} );

  closelog;
  exit;
}

# Look for a due schedule

my (undef, undef, $hour, $mday, undef, undef, $wday, undef, undef) = localtime;

$hour = 1 << $hour;
$wday = 1 << $wday;
$mday = 1 << $mday;

foreach my $schedule (keys %schedules)
{
  next unless ($schedules{$schedule}{'enable'});        # Must be enabled

  next unless ($schedules{$schedule}{'mday'} & $mday or # Must be due today
               $schedules{$schedule}{'wday'} & $wday);

  next unless ($schedules{$schedule}{'hours'} & $hour); # Must be due this hour

  debug 1, "Schedule $schedule due";

  execute_schedule( $schedule, $schedules{$schedule} );
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

  # Check that at least one of the contacts is enabled

  foreach my $contact (split '\|', $$schedule{'email'})
  {
    push @contacts, $contact if (exists $contacts{$contact} and $contacts{$contact}{'enable'});
  }

  if (not @contacts)
  {
    debug 1, "No enabled contacts";
    return;
  }

  log_message LOG_INFO, "Executing status mail schedule $name";

  # Create message

  my $message = new StatusMail( 'format'   => $$schedule{'format'},
                                'subject'  => $$schedule{'subject'},
                                'to'       => [ @contacts],
                                'sender'   => $mailsettings{'SENDER'},
                                'contacts' => \%contacts,
                                'lines'    => $$schedule{'lines'} );

  $message->calculate_period( $$schedule{'period-value'}, $$schedule{'period-unit'} );

  # Loop through the various log items

  foreach my $section ( sort keys %sections )
  {
    debug 2, "Section $section";
    $message->add_section( $section );

    foreach my $subsection ( sort keys %{ $sections{$section} } )
    {
      debug 2, "Subsection $subsection";
      $message->add_subsection( $subsection );

      foreach my $item ( sort keys %{ $sections{$section}{$subsection} } )
      {
        debug 2, "Item $item";

        my $key = "$section||$subsection||$item";

        next unless (exists $$schedule{"enable_$key"} and $$schedule{"enable_$key"} eq 'on');
        next unless ($sections{$section}{$subsection}{$item}{'format'} eq 'both' or
                     $sections{$section}{$subsection}{$item}{'format'} eq $$schedule{'format'});

        $message->add_title( $item );

        my $function = $sections{$section}{$subsection}{$item}{'function'};

        if (exists $$schedule{"value_$key"})
        {
          &$function( $message, $$schedule{"value_$key"} );
        }
        else
        {
          &$function( $message );
        }
      }

      $message->clear_cache;
    }
  }

  # End the Message

  debug 1, "Send mail message";
  $message->send;
}


#------------------------------------------------------------------------------
# sub add_mail_item( params )
#
# Adds a possible status item to the section and subsection specified.
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
#
# The option is sanity checked but otherwise ignored by this script.
#------------------------------------------------------------------------------

sub add_mail_item( % )
{
  my %params = @_;


  return unless (exists $params{'section'}    and
                 exists $params{'subsection'} and
                 exists $params{'item'}       and
                 exists $params{'function'} );

  if ($params{'option'})
  {
    return unless (ref $params{'option'} eq 'HASH');

    if ($params{'option'}{'type'} eq 'select')
    {
      return unless (ref $params{'option'}{'values'} eq 'ARRAY' and @{ $params{'option'}{'values'} } > 2);
    }
    elsif ($params{'option'}{'type'} eq 'integer')
    {
      return unless ($params{'option'}{'min'} and $params{'option'}{'max'} and $params{'option'}{'min'} < $params{'option'}{'max'});
    }
    else
    {
      return;
    }
  }

  $params{'format'} = 'both' unless (exists $params{'format'});

  $sections{$params{'section'}}{$params{'subsection'}}{$params{'item'}} = { 'function' => $params{'function'},
                                                                            'format'   => $params{'format'} };
}


#------------------------------------------------------------------------------
# sub abort( message, parameters... )
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
# Logs a message
#
# Parameters:
#   level   Severity of message
#   message Message to be logged
#------------------------------------------------------------------------------

sub log_message( $$ )
{
  my ($level, $message) = @_;

  print "($level) $message\n" if (-t STDIN);
#  syslog( $level, $message );
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


#------------------------------------------------------------------------------
# sub read_settings( file, hash )
#
# Reads the hash from the named file.  Handles a hash of hashes.
#------------------------------------------------------------------------------

sub read_settings( $$ )
{
  my ($file, $hash) = @_;

  my $item= '';

  open IN, '<', $file or die "Can't open $file for input: $!";

  foreach my $line (<IN>)
  {
    chomp $line;

    next unless ($line);

    if ($line =~ m/^\[(.*)\]$/)
    {
      $item = $1;
    }
    else
    {
      my ($field, $value) = split /\s*=\s*/, $line, 2;

      $$hash{$item}{$field} = $value;
    }
  }

  close IN;
}
