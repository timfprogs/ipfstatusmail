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

use lib "/var/ipfire/statusmail";

#------------------------------------------------------------------------------

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
