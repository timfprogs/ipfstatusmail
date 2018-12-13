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

use HTML::Entities;
use MIME::Lite;
use IPC::Open2;
use IO::Select;
use Socket;

require "/var/ipfire/general-functions.pl";
require "${General::swroot}/lang.pl";

package EncryptedMail;

############################################################################
# Configuration variables
############################################################################

my $gpg = "/usr/bin/gpg --homedir ${General::swroot}/statusmail/keys";

############################################################################
# Function prototypes
############################################################################

sub new( @ );
sub send( $@ );
sub add( $@ );
sub add_text( $@ );
sub add_table( $@ );
sub _add_table_text( $@ );
sub _add_table_html( $@ );
sub add_section( $$ );
sub add_subsection( $$ );
sub add_title( $$ );
sub is_html( $ );
sub is_text( $ );
sub get_max_lines_per_item( $ );

#------------------------------------------------------------------------------
# sub new( params )
#
# Creates a new mail message.
#
# Parameters:
#   A hash which can contain the following fields:
#     format    format of the message: 'html' or 'text'
#     to        reference to a list of contact names.
#     subject   subject for email message
#     sender    email address of sender
#     contacts  reference to hash of contacts
#
# The contacts hash contains a hash for each contact, indexed on the contact
# name.  Each contact must have an 'email' field containing the email address
# and may have a 'fingerprint' field containing the fingerprint of the PGP key
# used to encrypt the message for that contact.  If no fingerprint is given the
# message to that contact will be signed but not encrypted.
#------------------------------------------------------------------------------

sub new( @ )
{
  my $invocant = shift;

  my $class = ref($invocant) || $invocant;

  my $self     = { 'message'                => '',
                   'format'                 => 'html',
                   'in_section'             => 0,
                   'in_subsection'          => 0,
                   'in_item'                => 0,
                   'section'                => '',
                   'subsection'             => '',
                   'subject'                => 'Encrypted email',
                   'empty'                  => 1,
                   'skip_blank_sections'    => 0,
                   'skip_blank_subsections' => 0,
                   'image_file'             => 'img0000',
                   'max_lines_per_item'     => 100,
                   @_ };

  bless( $self, $class );

  # For an HTML message, put the head on the beginning.

  if ($self->{'format'} eq 'html')
  {
    $self->{'message'} = "<html>\n<head>\n";

    if ($self->{'stylesheet'})
    {
      $self->{'message'} .= "<style>\n";

      open STYLE, '<', $self->{'stylesheet'} or die "Can't open stylesheet: $!";

      $self->{'message'} .= $_ while <STYLE>;

      close STYLE;

      $self->{'message'} .= "</style>\n";
    }

    $self->{'message'} .= "</head>\n<body>\n<div id='header'><h1>";
    $self->{'message'} .= $self->{subject};
    $self->{'message'} .= "</h1></div>\n<div class='bigbox'>\n";
  }
  else
  {
    $self->{'message'} .= "$self->{subject}\n\n"
  }

  $self->{'to'} =~ s/\|/ /g if ($self->{'to'});

  # Create an email message object

  $self->{'object'} = MIME::Lite->new( Type     => 'multipart/related',
                                       Encoding => 'binary' );

  # Create the main part of the message

  if ($self->{format} eq 'html')
  {
    $self->{'text'} = $self->{'object'}->attach( Type     => 'text/html',
                                                 Encoding => '8bit' );
  }
  else
  {
    $self->{'text'} = $self->{'object'}->attach( Type     => 'TEXT',
                                                 Encoding => '8bit' );
  }

  return $self;
}


#------------------------------------------------------------------------------
# sub is_html()
#
# Returns true if the message format is HTML.
#------------------------------------------------------------------------------

sub is_html( $ )
{
  return shift->{'format'} eq 'html';
}


#------------------------------------------------------------------------------
# sub is_text()

# Return true if the message format is text.
#------------------------------------------------------------------------------

sub is_text( $ )
{
  return not shift->{'format'} eq 'html';
}


#------------------------------------------------------------------------------
# sub get_max_lines_per_item()

# Return true if the message format is text.
#------------------------------------------------------------------------------

sub get_max_lines_per_item( $ )
{
  return shift->{'max_lines_per_item'};
}


#------------------------------------------------------------------------------
# sub send( subject )
#
# Sends the message.  A subject may be specified which overrides the one
# specified when creating the object.
#------------------------------------------------------------------------------

sub send( $@ )
{
  use IPC::Open2;

  my $self = shift;
  my ($subject) = @_;

  # Don't do anything if there's no data

  return if ($self->{'empty'});

  $subject ||= $self->{'subject'};

  # Get the list of recipients, dividing it into signed and encrypted.

  my @signed_recipients;
  my @encrypted_recipients;

  foreach my $recipient ( @{ $self->{'to'} } )
  {
    if ($self->{'contacts'}{$recipient}{'fingerprint'})
    {
      # Signed and encrypted

      push @encrypted_recipients, $self->{'contacts'}{$recipient}{'email'};
    }
    else
    {
      # Signed only

      push @signed_recipients, $self->{'contacts'}{$recipient}{'email'};
    }
  }

  return unless (@encrypted_recipients or @signed_recipients);

  # Build the data that's going to be signed

  if ($self->{format} eq 'html')
  {
    $self->{message} .= "</div>\n" if ($self->{in_item});
    $self->{message} .= "</div>\n" if ($self->{in_subsection});
    $self->{message} .= "</div>\n" if ($self->{in_section});

    $self->{message} .= "</div>\n</body>\n</html>\n";
  }
  $self->{in_section} = 0;

  $self->{text}->data( $self->{message} );

  # Prepare to sign the data

  my ($from_gpg, $to_gpg);

  my $body        = $self->{'object'}->as_string;

  # Sign the data
  # Create a process running GPG

  my $cmd = "$gpg --batch --detach-sign --digest-algo sha256 --armour --local-user \"<$self->{'sender'}>\" --passphrase-fd 0";

  my $childpid = open2( $from_gpg, $to_gpg, $cmd );

  print $to_gpg "ipfirestatusemail\n";

  # Pipe the data to be signed to GPG

  foreach my $line (split /[\n]/, $body)
  {
    chomp $line;
    $line =~ s/\s*$/\r\n/;

    print $to_gpg $line;
  }

  print $to_gpg "\r\n";

  close $to_gpg;

  # Get the signature

  my $signature = '';

  $signature .= $_ while <$from_gpg>;

  waitpid( $childpid, 0);

  # Create the message that will contain the data and its signature

  my $signed_message = new MIME::Lite(Type    => 'multipart/mixed' );

  $signed_message->attr( 'content-type'          => 'multipart/signed' );
  $signed_message->attr( 'content-type.protocol' => 'application/pgp-signature' );
  $signed_message->attr( 'content-type.micalg'   => 'pgp-sha256' );

  # Attach the signed data to the message

  $signed_message->attach( $self->{'object'} );

  delete $self->{object};

  # Attach the signature to the message

  $signed_message->attach( Type     => 'application/pgp-signature',
                           Encoding => '7bit',
                           Data     => $signature );

  # Send the message to signed only recipients

  if (@signed_recipients)
  {
    $signed_message->add( From    => $self->{'sender'} );
    $signed_message->add( To      => @signed_recipients );
    $signed_message->add( Subject => $self->{'subject'} );

    $signed_message->send();

    # Delete tags that are not needed when the message is encrypted.

    $signed_message->delete( 'From' );
    $signed_message->delete( 'To' );
    $signed_message->delete( 'Subject' );
  }

  # Encrypt and send the message to signed and encrypted recipients

  if (@encrypted_recipients)
  {
    # Find the keys of the recipients and build the GPG command

    $cmd = "$gpg --batch --encrypt --armour --always-trust";

    foreach my $recipient ( @{ $self->{'to'} } )
    {
      if ($self->{'contacts'}{$recipient}{'fingerprint'})
      {
        my $fingerprint = $self->{'contacts'}{$recipient}{'fingerprint'};
        $fingerprint =~ s/\s+//g;

        $cmd .= " --recipient $fingerprint";
      }
    }

    # Build a mask to check if there's any output from GPG later

    my $reader = IO::Select->new;

    my $encrypted = '';

    # Start GPG and pipe the signed message to it

    $childpid = open2( $from_gpg, $to_gpg, $cmd ) or die "Can't fork GPG child: $!";

    $reader->add( $from_gpg );

    my $signed_data = $signed_message->as_string;
    my $read;

    foreach my $line (split /[\n]/, $signed_data)
    {
      chomp $line;
      $line =~ s/\s*$/\r\n/;
      print $to_gpg $line;

      while ($reader->can_read( 0 ))
      {
        $encrypted .= <$from_gpg>;
      }
    }

    close $to_gpg;

    $encrypted .= $_ while (<$from_gpg>);

    # Create the message that will contain the data and its signature

    my $encrypted_message = new MIME::Lite( From    => $self->{'sender'},
                                            To      => @encrypted_recipients,
                                            Subject => $self->{'subject'},
                                            Type    => 'multipart/mixed' );

    $encrypted_message->attr( 'content-type'          => 'multipart/encrypted' );
    $encrypted_message->attr( 'content-type.protocol' => 'application/pgp-encrypted' );

    # Attach the control information to the message

    $encrypted_message->attach( Type     => 'application/pgp-encrypted',
                                Encoding => '7bit',
                                Data     => 'Version 1' );

    # Attach the encrypted data

    $encrypted_message->attach( Type     => 'application/octet-stream',
                                Encoding => '7bit',
                                Data     => $encrypted );

    $encrypted_message->send();
  }
}


#------------------------------------------------------------------------------
# add_section( name )
#
# Starts a new section in the message.  Nothing is actually added to the
# message until the contents of an item are added.  This allows empty sections
# to be omitted.
#------------------------------------------------------------------------------

sub add_section( $$ )
{
  my ($self, $name) = @_;

  if ($self->{format} eq 'html')
  {
    $self->{message}    .= "</div>\n" if ($self->{in_item});
    $self->{message}    .= "</div>\n" if ($self->{in_subsection});
    $self->{message}    .= "</div>\n" if ($self->{in_section});
    $self->{section}     = "<div class='section'><h2>$name</h2>\n";
  }
  else
  {
    $self->{section}     = "\n$name\n";
    $self->{section}    .= '-' x length($name);
    $self->{section}    .= "\n";
  }

  $self->{subsection}    = '';
  $self->{item}          = '';

  $self->{in_section}    = 0;
  $self->{in_subsection} = 0;
  $self->{in_item}       = 0
}


#------------------------------------------------------------------------------
# sub add_subsection( name )
#
# Starts a new subsection in the message.  Nothing is actually added to the
# message until the contents of an item are added.  This allows empty
# subsections to be omitted.
#------------------------------------------------------------------------------

sub add_subsection( $$ )
{
  my ($self, $name) = @_;

  if ($self->{format} eq 'html')
  {
    $self->{message}    .= "</div>\n" if ($self->{in_item});
    $self->{message}    .= "</div>\n" if ($self->{in_subsection});
    $self->{subsection}  = "<div class='subsection'><h3>$name</h3>\n";
  }
  else
  {
    $self->{subsection}  = "\n  $name\n";
  }

  $self->{item}          = '';

  $self->{in_subsection} = 0;
  $self->{in_item}       = 0
}


#------------------------------------------------------------------------------
# sub title( name )
#
# Adds a new item title to the message.  Nothing is actually added to the
# message until the contents of an item are added.  This allows empty items to
# be omitted.
#------------------------------------------------------------------------------

sub add_title( $$ )
{
  my ($self, $string) = @_;

  if ($self->{format} eq 'html')
  {
    $self->{message}    .= "</div>\n" if ($self->{in_item});
    $self->{item} = "<div class='item'><h4>$string</h4>\n";
  }
  else
  {
    $self->{item} = "\n    $string\n\n";
  }

  $self->{in_item}       = 0;
}


#------------------------------------------------------------------------------
# sub add( lines )
#
# Adds an item (or part of an item) to the message. If there are section,
# subsection or item titles outstanding, they are added, and then the contents
# of the parameter array is added.  No formatting is carried out.  This
# function should generally only be used by a plug in to add pre-formatted
# HTML to the message.
#------------------------------------------------------------------------------

sub add( $@ )
{
  my ($self, @lines) = @_;

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

  foreach my $line (@lines)
  {
    $self->{message} .= $line;
  }

  $self->{empty} = 0;
}


#------------------------------------------------------------------------------
# sub add_text( lines )
#
# Adds the textual lines to the message.  If there are section, subsection or
# item titles outstanding, they are added, and then the contents of the
# parameter array is added.  The lines are formatted as plain text with HTML
# breaks inserted if necessary.
#------------------------------------------------------------------------------

sub add_text( $@ )
{
  my ($self, @lines) = @_;

  my $message = '';

  foreach my $string (@lines)
  {
    if ($self->{format} eq 'html')
    {
      $string =~ s/[\n\r]+/<br>\n/g;
      $message .= $string;
    }
    else
    {
      foreach my $string ( split /[\n\r]+/, $string )
      {
        $message .= '    ' . $string . "\n";
      }
    }
  }

  $self->add( $message );

  $self->{empty} = 0;
}


#------------------------------------------------------------------------------
# sub add_image( params )
#
# Adds an image to the message.
#------------------------------------------------------------------------------

sub add_image( $@ )
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

  if ($params{'type'} eq 'image/jpeg')
  {
    $image_name .= '.jpg';
  }
  elsif ($params{'type'} eq 'image/gif')
  {
    $image_name .= '.gif';
  }
  elsif ($params{'type'} eq 'image/png')
  {
    $image_name .= '.png';
  }
  else
  {
    return;
  }

  my $data;

  if (exists $params{fh})
  {
    my $buffer;
    binmode $params{fh};

    while (read $params{fh}, $buffer, 1024)
    {
      $data .= $buffer;
    }
  }
  elsif (exists $params{data})
  {
    $data = $params{data};
  }

  my $name = $params{'name'} || $image_name;

  $self->{object}->attach( Type     => $params{'type'},
#                           Filename => $name,
                           Data     => $data,
                           Id       => $image_name );

  $self->{message} .= "<img src='cid:$image_name'";
  $self->{message} .= " alt='$params{alt}'" if (exists $params{alt});
  $self->{message} .= ">\n";

  $self->{empty}    = 0;
}

#------------------------------------------------------------------------------
# sub add_table( contents )
#
# Adds a table to the message. If there are section, subsection or item titles
# outstanding, they are added, and then the contents of the parameter array are
# added.
#
# The parameters passed should be an array of references to arrays.  Each entry
# in the parameter array is a reference to an array representing a row of the
# table.  The first row is taken to be the header.
#
# The entire table is scanned to work out the size and alignment of each column
# and then the table is formatted and added to the message.  Columns are right
# aligned if they only contain numeric data (which may be suffixed to indicate
# units), otherwise columns are left aligned.  The header row is centered.  The
# alignment algorithm may be overridden by inserting a row consisting only of
# entries containing the following characters: '<', '|', '#' and '>', for left
# centre, numeric and right alignment.  This line will override the alignment
# for subsequent columns.  This also works for the header row, by inserting
# the alignment information before the header row; in this case the entire body
# of the table must also be manually aligned.
#------------------------------------------------------------------------------

sub add_table( $@ )
{
  my ($self, @lines) = @_;

  if ($self->{format} eq 'html')
  {
    _add_table_html( $self, @lines );
  }
  else
  {
    _add_table_text( $self, @lines );
  }

  $self->{empty} = 0;
}


#------------------------------------------------------------------------------
# _add_table_html( contents )
#
# Internal subroutine called by add_table to format a table in HTML.
#------------------------------------------------------------------------------

sub _add_table_html( $@ )
{
  my ($self, @lines) = @_;
  my @align;
  my $header_row     = 1;
  my $text           = '';
  my $number_lines   = 0;
  my $centre_header  = 1;

  # Scan through the table entries to work out the alignment of each column.
  # Note that the header row is always centre aligned, unless the alignment of
  # entire table is set manually.

  foreach my $line ( @lines )
  {
    my @fields = @{ $line };

    unless ($align[0])
    {
      for (my $column = 0 ; $column < @fields ; $column++)
      {
        # Initialise to right aligned.

        $align[$column] = '>';
      }
    }

    # Check for manually defined alignment.

    last if ((join '', @fields) !~ m/[^<>|#]/);

    for (my $column = 0 ; $column < @fields ; $column++)
    {
      # Handle multiple lines in a single table cell.

      foreach my $item (split /[\n\r]+/, $fields[$column])
      {
        if (not $header_row and $align[$column] ne '<')
        {
          if ($align[$column] eq '>' and ($fields[$column] =~ m/^\d*\.\d*(?:\s*[-\w\/%]+)?$/))
          {
            # Decimal number - number align.
            # Note that a number may be followed by a suffix (e.g. unit).

            $align[$column] = '#';
          }
          elsif ($align[$column] ne '<' and $fields[$column] !~ m/^(?:\d*\.)?\d+(?:\s*[-\w\/%]+)?$/)
          {
            # Alphanumeric - left align.

            $align[$column] = '<';
          }
        }
      }
    }

    $header_row = 0;
  }

  # Now scan the table again, outputting the information.

  $header_row = 1;

  $text = "<table>\n";

  foreach my $line ( @lines )
  {
    my @fields      = @{ $line };

    $text .= "<tr>";

    if ((join '', @fields) !~ m/[^<>|#]/)
    {
      # Explicit alignment.

      for (my $column = 0 ; $column < @fields ; $column++)
      {
        $align[$column] = $fields[$column] if ($fields[$column]);
      }

      # Override the centre justification of the header.

      $centre_header = 0;

      next;
    }

    for (my $column = 0 ; $column < @fields ; $column++)
    {
      my $item  = $fields[$column];
      my $tag   = 'td';
      my $align = ' style="text-align: right"';

      $item  =~ s/[\n\r]+/<br>/g;
      $align = ' style="text-align: center"' if ($align[$column] eq '|');
      $align = ''                            if ($align[$column] eq '<');

      if ($header_row)
      {
        $tag   = 'th';
        $align = '' if ($centre_header);
      }

      $text .= "<$tag$align>$item</$tag>";
    }

    $text .= "</tr>\n";
    $header_row = 0;
    last if (++$number_lines > $self->{'max_lines_per_item'});
  }

  $text .= "</table>\n";

  $self->add( $text );
  $self->{empty}    = 0;
}

#------------------------------------------------------------------------------
# sub _add_table_text( contents )
#
# Internal subroutine called by add_table to format a table in text.
#------------------------------------------------------------------------------

sub _add_table_text( $@ )
{
  my ($self, @lines) = @_;
  my @width;
  my @align;
  my $header_row     = 1;
  my $ignore_align   = 0;
  my $text           = '';
  my $number_lines   = 0;
  my $centre_header  = 1;

  # Scan through the table entries to work out the width and alignment of each
  # column.
  # Note that the header row is always centre aligned, unless the alignment of
  # entire table is set manually.

  foreach my $line ( @lines )
  {
    my @fields = @{ $line };

    unless ($align[0])
    {
      for (my $column = 0 ; $column < @fields ; $column++)
      {
        # Initialise to zero width and right aligned.

        $width[$column] = 0;
        $align[$column] = '>';
      }
    }


    # Check for manually defined alignment.

    if ((join '', @fields) !~ m/[^<>|#]/)
    {
      $ignore_align = 1;
      next;
    }

    for (my $column = 0 ; $column < @fields ; $column++)
    {
      next unless ($fields[$column]);

      # Handle multiple lines in a single table cell.

      foreach my $item (split /[\n\r]+/, $fields[$column])
      {
        next unless ($item);

        if (length $item > $width[$column])
        {
          $width[$column] = length $item;
        }

        if (not $header_row and $align[$column] ne '<' and not $ignore_align)
        {
          if ($align[$column] eq '>' and ($item =~ m/^\d*\.\d*(?:\s*[-\w\/%]+)?$/))
          {
            # Decimal number - number align.
            # Note that a number may be followed by a suffix (e.g. unit).

            $align[$column] = '#';
          }
          elsif ($align[$column] ne '<' and $item !~ m/^(?:\d*\.)?\d+(?:\s*[-\w\/%]+)?$/)
          {
            # Alphanumeric - left align.

            $align[$column] = '<';
          }
        }
      }
    }

    last if (++$number_lines > $self->{'max_lines_per_item'});
    $header_row = 0;
  }

  # Now scan the table again, outputting the information.

  $header_row   = 1;
  $number_lines = 0;

  foreach my $line ( @lines )
  {
    my @fields      = @{ $line };
    my @next_fields = ();
    my $more_lines  = 0;

    if ((join '', @fields) !~ m/[^<>|#]/)
    {
      # Explicit alignment.

      for (my $column = 0 ; $column < @fields ; $column++)
      {
        $align[$column] = $fields[$column] if ($fields[$column]);
      }

      # Override the centre justification of the header.

      $centre_header = 0;

      next;
    }

    $text .= '    ';

    for (my $column = 0 ; $column < @fields ; $column++)
    {
      my $item              = '';
      $next_fields[$column] = '';

      # Try to split the cell into multiple lines.

      ($item, $next_fields[$column]) = split /[\n\r]+/, $fields[$column], 2;

      if ($next_fields[$column])
      {
        $more_lines = 1 ;
      }
      else
      {
        $next_fields[$column] = ' ';
      }

      $item = '' unless ($item);

      my $width = length $item;

      if ($centre_header or $align[$column] eq '|')
      {
        # Centre justified pre-spacing.
        $text .= ' ' x (($width[$column] - $width) / 2 );
      }
      elsif ($align[$column] eq '>' or $align[$column] eq '#')
      {
        # Right justified pre-spacing.
        $text .= ' ' x ($width[$column] - $width);
      }

      $text .= $item;

      if ($column != $#fields)
      {
        if ($centre_header or $align[$column] eq '|')
        {
          # Centre justified post spacing.
          $text .= ' ' x (($width[$column] - $width + 1) / 2 );
        }
        elsif ($align[$column] eq '<')
        {
          # Left justified post spacing.
          $text .= ' ' x ($width[$column] - $width);
        }

        # Inter column spacing
        $text .= "  ";
      }
    }

    $text         =~ s/\s+$//;
    $text         .= "\n";
    $header_row    = 0;
    $centre_header = 0;

    if ($more_lines)
    {
      # One or more of the cells in this row has multiple lines outstanding.
      # Go back to output the next line.
      $line = [ @next_fields ];
      redo;
    }

    last if (++$number_lines > $self->{'max_lines_per_item'});
  }

  $self->add( $text );
  $self->{empty}    = 0;
}


1;
