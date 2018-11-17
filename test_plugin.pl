#!/usr/bin/perl

############################################################################
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

use Time::Local;

require "/var/ipfire/general-functions.pl";
require "${General::swroot}/lang.pl";

# Variables

my $testdir    = '/var/ipfire/statusmail/test';
my $stylesheet = '/var/ipfire/statusmail/stylesheet.css';
my %items;
our $plugin;

my $start_time    = 0;
my @start_time    = ();
my $end_time      = 0;
my @end_time      = ();
my $weeks_covered = 0;

# Function prototypes

sub add_mail_item( @ );
sub get_period_start();
sub get_period_end();
sub get_weeks_covered();
sub cache( $;$ );

sub choices( $@ );
sub integer( $$$ );
sub yesno( $ );
sub get_period;

# Main function

foreach $plugin (@ARGV)
{
  if (-e $plugin)
  {
    require $plugin;
  }
  else
  {
    print "Can't find plugin $plugin\n";
  }
}

if (not %items)
{
  print "No valid plugins found\n";
  exit;
}

mkdir $testdir unless (-d $testdir);

# Ask for options

my $format       = choices( 'Message format', 'html', 'text' );

# Create message

my $message = new TestStatusMail( format => $format, stylesheet => $stylesheet, subject => 'Test email' );

get_period ( $message );

$message->{'max_lines_per_item'} = integer( 'Maximum lines per item', 1, 1000 );

# Loop through the various log items

foreach my $section ( sort keys %items )
{
  $message->add_section( $section );

  foreach my $subsection ( sort keys %{ $items{$section} } )
  {
    $message->add_subsection( $subsection );

    foreach my $item ( sort keys %{ $items{$section}{$subsection} } )
    {
      next unless ($items{$section}{$subsection}{$item}{'format'} eq 'both' or
                   $items{$section}{$subsection}{$item}{'format'} eq $format);

      if (yesno( "Add item $section : $subsection : $item ? " ))
      {
        $message->add_title( $item );

        my $function = $items{$section}{$subsection}{$item}{'function'};

        if (exists $items{$section}{$subsection}{$item}{'option'})
        {
          if ($items{$section}{$subsection}{$item}{'option'}{'type'} eq 'select')
          {
            my $option = choices( $items{$section}{$subsection}{$item}{'option'}{'name'},
                                  @{$items{$section}{$subsection}{$item}{'option'}{'values'} } );

            &$function( $message, $option );
          }
          else
          {
            my $value = integer( $items{$section}{$subsection}{$item}{'option'}{'name'},
                                 $items{$section}{$subsection}{$item}{'option'}{'min'},
                                 $items{$section}{$subsection}{$item}{'option'}{'max'} );

            &$function( $message, $value );
          }
        }
        else
        {
          &$function( $message );
        }
      }
    }
  }
}

$message->print( $testdir );

exit;


#------------------------------------------------------------------------------
# sub choices( text, options )
#
# Asks the user for an option from the provided list.
#
# Parameters:
#   text    the question to ask the user
#   options list of options
#
# Returns:
#   the selected option
#------------------------------------------------------------------------------

sub choices( $@ )
{
  my ($text, @options) = @_;

  my $selection = '';
  my %options;
  my @display;

  foreach my $option (@options)
  {
    my ($name, $value) = split /:/, $option;

    $value ||= $name;

    $options{$name} = $value;
    push @display, $name;
  }

  while (not $selection)
  {
    print "Select $text from the following options: " . join( ', ', @display ) . ": ";

    my $line = <STDIN>;

    chomp $line;

    ($selection) = grep /^$line/i, @display;
  }

  return $options{$selection};
}


#------------------------------------------------------------------------------
# sub yesno( text )
#
# Asks the user for a yes or no option.
#
# Parameters:
#   text    the question to ask the user
#
# Returns:
#   true for yes, false for no
#------------------------------------------------------------------------------

sub yesno( $)
{
  my ($text) = @_;

  my $selection = '';

  while (not $selection)
  {
    print "$text";

    my $line = <STDIN>;

    chomp $line;

    ($selection) = grep /$line/i, ( 'yes', 'no' );
  }

  return $selection eq 'yes';
}


#------------------------------------------------------------------------------
# sub integer( text, min, max )
#
# Asks the user for an integer within the specified limits.
#
# Parameters:
#   text    the question to ask the user
#   min     minimum value of input
#   max     maximum value of input
#
# Returns:
#   the selected value
#------------------------------------------------------------------------------

sub integer( $$$ )
{
  my ($text, $min, $max) = @_;

  my $value;

  while (not defined $value)
  {
    print "Select $text ($min..$max):";

    my $line = <STDIN>;

    chomp $line;

    next if ($line =~ m/\D+/);
    next unless ($line =~ m/\d/);
    next if ($line < $min);
    next if ($line > $max);

    $value = $line;
  }

  return $value;
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
#------------------------------------------------------------------------------

sub add_mail_item( @ )
{
  my %params = @_;

  if (not exists $params{'section'})
  {
    print "Plugin $plugin has no section specified\n";
    return;
  }

  if (not exists $params{'subsection'})
  {
    print "Plugin $plugin has no subsection specified\n";
    return;
  }

  if (not exists $params{'item'})
  {
    print "Plugin $plugin has no item specified\n";
    return;
  }

  if (not exists $params{'function'})
  {
    print "Plugin $plugin has no function specified\n";
    return;
  }

  if ($params{'option'})
  {
    unless (ref $params{'option'} eq 'HASH')
    {
      print "Plugin $plugin option incorrectly specified - should be hash\n";
    }

    unless ($params{'option'}{'type'})
    {
      print "Plugin $plugin has no option type specified\n";
      return;
    }

    unless ($params{'option'}{'name'})
    {
      print "Plugin $plugin has no option name specified\n";
      return;
    }

    if ($params{'option'}{'type'} eq 'select')
    {
      unless (ref $params{'option'}{'values'} eq 'ARRAY' and @{ $params{'option'}{'values'} } > 1)
      {
        print "Plugin $plugin select option values incorrectly specified\n";
        return;
      }
    }
    elsif ($params{'option'}{'type'} eq 'integer')
    {
      unless (exists $params{'option'}{'min'} and exists $params{'option'}{'max'} and $params{'option'}{'min'} < $params{'option'}{'max'})
      {
        print "Plugin $plugin integer option limits not correctly specified\n";
        print "No minimum value specified\n"       unless (exists $params{'option'}{'min'});
        print "No maximum value specified\n"       unless (exists $params{'option'}{'max'});
        print "Maximum not greater than minimum\n" unless (exists $params{'option'}{'min'} and
                                                           exists $params{'option'}{'min'} and
                                                           $params{'option'}{'min'} < $params{'option'}{'max'});
      }
    }
    else
    {
      print "Plugin $plugin has invalid option $params{'option'}{'type'}\n";
      return;
    }
  }

  if ($params{'format'} and $params{'format'} ne 'html' and $params{'format'} ne 'text' and $params{'format'} ne 'both')
  {
    print "Plugin $plugin has invalid format\n";
  }

  $params{'format'} = 'both' unless (exists $params{'format'});

  $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}} = { 'function' => $params{'function'},
                                                                         'format'   => $params{'format'} };

  if ($params{'option'})
  {
    if ($params{'option'}{'type'} eq 'select')
    {
      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'type'}   = $params{'option'}{'type'};
      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'values'} = $params{'option'}{'values'};
      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'name'} = $params{'option'}{'name'};
    }
    elsif ($params{'option'}{'type'} eq 'integer')
    {
      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'type'} = $params{'option'}{'type'};
      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'min'}  = $params{'option'}{'min'};
      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'max'}  = $params{'option'}{'max'};
      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'name'} = $params{'option'}{'name'};
    }
  }
}


#------------------------------------------------------------------------------
# sub get_period
#
# Gets the period covered by a report
#------------------------------------------------------------------------------

sub get_period
{
  my $self = shift;

  my @monthnames = ('Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' );

  my $unit  = choices( 'Period covered by report', 'hours', 'days', 'weeks', 'months' );
  my $value = integer( "$unit covered by report", 1, 365 );

  $self->calculate_period( $value, $unit );
}

package TestStatusMail;

use base qw/StatusMail/;

sub print( $$ )
{
  my $self = shift;
  my $dir  = shift;
  my $file = "$dir/test.txt";

  if ($self->{'empty'})
  {
    print "No output produced\n";
    return;
  }

  if ($self->{format} eq 'html')
  {
    $self->{message} .= "</div>\n" if ($self->{in_item});
    $self->{message} .= "</div>\n" if ($self->{in_subsection});
    $self->{message} .= "</div>\n" if ($self->{in_section});

    $self->{message} .= "</div>\n</body>\n</html>\n";
    $file             = "$dir/test.html";
  }

  open OUT, '>', $file or die "Can't open test output file $file: $!";

  print OUT $self->{message};

  close OUT;

  print "Output is in $file\n";
}

sub add_image
{
  my ($self, %params) = @_;

  if ($self->{section})
  {
    $self->{message}      .= $self->{section};
    $self->{section}       = '';
    $self->{in_section}    = 1;
    $self->{in_subsection} = 0;
    $self->{in_item}       = 0;
  }

  if ($self->{subsection})
  {
    $self->{message}      .= $self->{subsection};
    $self->{subsection}    = '';
    $self->{in_subsection} = 1;
    $self->{in_item}       = 0;
  }

  if ($self->{item})
  {
    $self->{message}   .= $self->{item};
    $self->{item}       = '';
    $self->{in_item}    = 1;
  }

  $self->{'image_file'}++;

  my $image_name = $self->{'image_file'};

  $image_name .= '.jpg' if ($params{'type'} eq 'image/jpeg');
  $image_name .= '.gif' if ($params{'type'} eq 'image/gif');
  $image_name .= '.png' if ($params{'type'} eq 'image/png');

  open OUT, '>', "test/$image_name" or die "Can't open image file $image_name: $!";
  binmode( OUT );

  if (exists $params{fh})
  {
    my $buffer;
    binmode $params{fh};

    while (read $params{fh}, $buffer, 1024)
    {
      print OUT $buffer;
    }
  }
  elsif (exists $params{data})
  {
    print OUT $params{data};
  }

  close OUT;

  $self->{message} .= "<img src='$image_name'";
  $self->{message} .= " alt='$params{alt}'" if (exists $params{alt});
  $self->{message} .= ">\n";

  $self->{empty}    = 0;
}

1;
