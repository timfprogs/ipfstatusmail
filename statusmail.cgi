#!/usr/bin/perl

###############################################################################
#                                                                             #
# IPFire.org - A linux based firewall                                         #
#                                                                             #
# This program is free software: you can redistribute it and/or modify        #
# it under the terms of the GNU General Public License as published by        #
# the Free Software Foundation, either version 3 of the License, or           #
# (at your option) any later version.                                         #
#                                                                             #
# This program is distributed in the hope that it will be useful,             #
# but WITHOUT ANY WARRANTY; without even the implied warranty of              #
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the               #
# GNU General Public License for more details.                                #
#                                                                             #
# You should have received a copy of the GNU General Public License           #
# along with this program.  If not, see <http://www.gnu.org/licenses/>.       #
#                                                                             #
###############################################################################

#enable only the following on debugging purpose
use strict;
use warnings;
use CGI qw/:standard/;
use CGI::Carp 'fatalsToBrowser';

use IPC::Open3;
use HTML::Entities;

require '/var/ipfire/general-functions.pl';
require "${General::swroot}/lang.pl";
require "${General::swroot}/header.pl";

###############################################################################
# Function prototypes
###############################################################################

# Used by plugins

sub add_mail_item( % );
sub get_period_start();
sub get_period_end();
sub get_weeks_covered();
sub cache( $;$ );

# Local functions

sub show_encryption_keys();
sub show_contacts();
sub show_schedules();
sub show_signing_key();
sub check_key( $ );
sub get_keys();
sub save_settings( $$ );
sub read_settings( $$ );
sub check_schedule( % );
sub clean( $ );
sub toggle_on_off( $ );

###############################################################################
# Configuration variables
###############################################################################

my $contacts             = "${General::swroot}/statusmail/contacts";
my $schedules            = "${General::swroot}/statusmail/schedules";
my $generate_signature   = "${General::swroot}/statusmail/generate_signature.sh";
my $mailsettings         = "${General::swroot}/dma/mail.conf";
my $mainsettings         = "${General::swroot}/main/settings";
my $plugin_dir           = "${General::swroot}/statusmail/plugins";
my $gpg                  = "/usr/bin/gpg --homedir ${General::swroot}/statusmail/keys";
my $execute              = '/usr/local/bin/statusmail.pl';
my $tmpdir               = '/var/tmp';

###############################################################################
# Initialize variables and hashes
###############################################################################

my %mainsettings         = ();
my %cgiparams            = ();
my $errormessage         = '';
my $current_contact      = '';
my $current_key  = '';
my $current_schedule     = '';
my $save_contacts        = 0;
my $save_schedules       = 0;
my %items;
my %color;
my %contacts;
my %schedules;
my %keys;
my %mailsettings;
my $sign_key;
my @debug;

###############################################################################
# Read all parameters for site
###############################################################################

Header::getcgihash(\%cgiparams);
General::readhash($mainsettings, \%mainsettings);
General::readhash($mailsettings, \%mailsettings) if (-e $mailsettings);
General::readhash("/srv/web/ipfire/html/themes/".$mainsettings{'THEME'}."/include/colors.txt", \%color);

if (-r $contacts)
{
  read_settings( $contacts, \%contacts );
}
else
{
  # No settings file - set up defaults

  %contacts = ();
}


if (-r $schedules)
{
  read_settings( $schedules, \%schedules );
}
else
{
  # No settings file - set up defaults

  %schedules = ();
}

get_keys();

# Scan for plugins

opendir DIR, $plugin_dir or die "Can't open Plug-in directory $plugin_dir: $!";

foreach my $file (readdir DIR)
{
  next unless ($file =~ m/\.pm$/);

  require "$plugin_dir/$file";
}

# Get the email signing key

$sign_key = `$gpg --armour --export IPFire`;

$sign_key =~ s/^\s+//;
$sign_key =~ s/\s+$//;

$errormessage .= "<p>$Lang::tr{'statusmail no signing key'}</p>" if ($sign_key =~ m/nothing exported/ or not $sign_key);

###############################################################################
# Start of HTTP/HTML output
###############################################################################

# Show Headers
Header::showhttpheaders();

###############################################################################
# ACTIONS
###############################################################################

# ACTIONS for Installed PGP Keys

if ($cgiparams{'KEY_ACTION'} eq $Lang::tr{'statusmail import'})
{
  check_key( $cgiparams{'key'} );

  get_keys();
}
elsif ($cgiparams{'KEY_ACTION'} eq 'remove key')
{
  my $key = $cgiparams{'KEY'};
  $key =~ s/\s+//g;

  my @output = `$gpg --batch --yes --delete-key $key 2>&1`;

  if ($?)
  {
    $errormessage .= join '<br>', "<p>$Lang::tr{'statusmail key remove failed'} $?", @output;
    $errormessage .= "</p>\n";
  }

  get_keys();
}

# ACTIONS for Signing Certificate

elsif ($cgiparams{'KEY_ACTION'} eq $Lang::tr{'statusmail generate'})
{
  system( "$generate_signature &>$tmpdir/statusmail_log &" );
}

# ACTIONS for Contacts

elsif ($cgiparams{'CONTACT_ACTION'} eq $Lang::tr{'add'} or $cgiparams{'CONTACT_ACTION'} eq $Lang::tr{'update'})
{
  if (not $cgiparams{'name'})
  {
    $errormessage .= "<p>$Lang::tr{'statusmail no contact name'}</p>";
  }

  if (not General::validemail( $cgiparams{'address'} ))
  {
    $errormessage .= "<p>$Lang::tr{'statusmail email invalid'}</p>";
  }

  if (not $errormessage)
  {
    my $enable = $contacts{$cgiparams{'name'}}{'enable'};

    $contacts{$cgiparams{'name'}} = { 'email'       => $cgiparams{'address'},
                                      'keyid'       => '',
                                      'fingerprint' => '',
                                      'enable'      => $enable };
    $save_contacts = 1;
  }
}
elsif ($cgiparams{'CONTACT_ACTION'} eq 'edit contact')
{
  $current_contact = $cgiparams{'KEY'};
}
elsif ($cgiparams{'CONTACT_ACTION'} eq 'remove contact')
{
  my $key = $cgiparams{'KEY'};

  delete $contacts{$key};
  $save_contacts = 1;
}
elsif ($cgiparams{'CONTACT_ACTION'} eq 'toggle contact')
{
  my $key = $cgiparams{'KEY'};

  toggle_on_off( $contacts{$key}{'enable'} );
  $save_contacts = 1;
}

# ACTIONS for Schedules

elsif ($cgiparams{'SCHEDULE_ACTION'} eq $Lang::tr{'add'} or $cgiparams{'SCHEDULE_ACTION'} eq $Lang::tr{'update'})
{
  check_schedule( %cgiparams );
}
elsif ($cgiparams{'SCHEDULE_ACTION'} eq 'edit schedule')
{
  $current_schedule = $cgiparams{'KEY'};
}
elsif ($cgiparams{'SCHEDULE_ACTION'} eq 'execute schedule')
{
  system( "$execute '$cgiparams{'KEY'}' &" );
}
elsif ($cgiparams{'SCHEDULE_ACTION'} eq 'remove schedule')
{
  my $key = $cgiparams{'KEY'};

  delete $schedules{$key};
  $save_schedules = 1;
}
elsif ($cgiparams{'SCHEDULE_ACTION'} eq 'toggle schedule')
{
  my $key = $cgiparams{'KEY'};

  toggle_on_off( $schedules{$key}{'enable'} );

  $save_schedules = 1;
}

###############################################################################
# Page contents
###############################################################################

Header::openpage($Lang::tr{'statusmail status emails'}, 1, '');

# Display error of email is not enabled

if ($mailsettings{'USEMAIL'} ne 'on')
{
  $errormessage .= "<p>$Lang::tr{'statusmail email not enabled'}</p>";
}

if ($errormessage)
{
  Header::openbox( '100%', 'left', $Lang::tr{'error messages'} );
  print "<font class='base'>$errormessage</font>\n";
  Header::closebox();
}

# Check for key generation in progress

my $return = `pidof generate_signature.sh -x`;

chomp($return);

if ($return)
{
  Header::openbox( 'Working', 1, "<meta http-equiv='refresh' content='3;'>$Lang::tr{'statusmail working'}" );

  print <<END;
  <table width='100%'>
    <tr>
      <td align='center'>
        <img src='/images/indicator.gif' alt='$Lang::tr{'aktiv'}' />&nbsp;
      <td>
    </tr>
    <tr>
      <td align='center'>
      <form method='post' action='$ENV{'SCRIPT_NAME'}'>
        <input type='image' alt='$Lang::tr{'reload'}' title='$Lang::tr{'reload'}' src='/images/view-refresh.png' />
      </form>
      </td>
    </tr>
    <tr><td align='left'><pre>
END
;
  my @output = `tail -20 $tmpdir/statusmail_log`;
  foreach (@output)
  {
    print "$_";
  }
  print <<END;
      </pre>
    </table>
END
;

  unlink "$tmpdir/statusmail_log";

  Header::closebox();
  Header::closebigbox();
  Header::closepage();
  exit;
}

# Show main bulk of page

if ($mailsettings{'USEMAIL'} eq 'on')
{
  show_signing_key();

  unless ($sign_key =~ m/nothing exported/ or not $sign_key)
  {
    show_encryption_keys();
    show_contacts();
    show_schedules();
  }
}

foreach my $line (@debug)
{
  print "$line<br>\n";
}

# End of page

Header::closebigbox();
Header::closepage();

# Save settings if necessary

save_settings( $contacts,  \%contacts )  if ($save_contacts);
save_settings( $schedules, \%schedules ) if ($save_schedules);

###############################################################################
# Subroutines
###############################################################################

#------------------------------------------------------------------------------
# sub show_signing_key()
#
# Outputs the 'Signing Key' section of the page.
#
# A new signing key can be generated.
#------------------------------------------------------------------------------

sub show_signing_key()
{
  # Email signing key

  Header::openbox('100%', 'left', $Lang::tr{'statusmail signing key'});

  print <<END
<table width='100%' cellspacing='1'>
  <tr>
    <td width='15%'>$Lang::tr{'statusmail signing key'}</td>
    <td>
      <textarea name='sign key' rows='5' cols='90' readonly id='key_out'>$sign_key</textarea>
    </td>
  </tr>
</table>
<br><hr>
<table width='100%'>
  <tr>
  <form method='post' action='$ENV{'SCRIPT_NAME'}'>
    <td align='right'>
      <button onclick='copy_clipboard()'>$Lang::tr{'statusmail copy to clipboard'}</button>
      <input type='submit' name='KEY_ACTION' value='$Lang::tr{"statusmail generate"}'></td>
  </form>
  </tr>
</table>
END
;

  Header::closebox();
}

#------------------------------------------------------------------------------
# sub show_encryption_keys()
#
# Outputs the 'Installed PGP Keys' section of the page.
#
# User keys can be imported or deleted.
#------------------------------------------------------------------------------

sub show_encryption_keys()
{
  Header::openbox('100%', 'left', $Lang::tr{'statusmail keys'});

  print <<END
  <script>
    function copy_clipboard() {
      /* Get the text field */
      var copyText = document.getElementById( "cert_out" );

      /* Select the text field */
      copyText.select();

      /* Copy the text inside the text field */
      document.execCommand( "copy" );

      /* Alert the copied text */
      alert( "$Lang::tr{'statusmail copied to clipboard'}" );
    }
  </script>
END
;

  # Install PGP keys

  print <<END
  <form method='post' action='$ENV{'SCRIPT_NAME'}'>
    <table width='100%' cellspacing='1'>
      <tr>
        <td width='15%'>$Lang::tr{'statusmail key'}</td>
        <td>
          <textarea name='key' rows='5' cols='90' id='cert_in' contenteditable="true">
          </textarea>
        </td>
      </tr>
    </table>
    <br><hr>
    <table width='100%'>
      <tr>
        <td align='right'>
          <input type='submit' name='KEY_ACTION' value='$Lang::tr{"statusmail import"}' />
        </td>
      </tr>
    </table>
    <hr>
  </form>
  <table width='100%' class='tbl'>
  <tr>
    <th width='20%'>$Lang::tr{'statusmail name'}</th>
    <th width='20%'>$Lang::tr{'statusmail email'}</th>
    <th width='15%'>$Lang::tr{'statusmail keyid'}</th>
    <th width='25%'>$Lang::tr{'statusmail fingerprint'}</th>
    <th width='10%'>$Lang::tr{'statusmail key expires'}</th>
    <th>$Lang::tr{'statusmail action'}</th>
  </tr>
END
;

  # List installed keys

  my $row = 0;
  foreach my $fingerprint (sort keys %keys)
  {
    my $show_fingerprint = $fingerprint;
    $show_fingerprint =~ s/((?:\w{4}\s){4}(?:\w{4}))\s(.+)/$1<br>$2/;

    if ($row % 2)
    {
      print "<tr bgcolor='$color{'color20'}'>";
    }
    else
    {
      print "<tr bgcolor='$color{'color22'}'>";
    }

    my $name  = clean( $keys{$fingerprint}{'userid'} );
    my $email = clean( $keys{$fingerprint}{'email'} );

    print <<END
  <td align='center'>$name</td>
  <td align='center'>$email</td>
  <td align='center'>$keys{$fingerprint}{'keyid'}</td>
  <td align='center'>$show_fingerprint</td>
  <td align='center'>$keys{$fingerprint}{'expires'}</td>
  <td align='center'>
  <form method='post' action='$ENV{'SCRIPT_NAME'}'>
  <input type='hidden' name='KEY_ACTION' value='remove key' />
  <input type='image' name='$Lang::tr{'remove'}' src='/images/delete.gif' alt='$Lang::tr{'remove'}' title='$Lang::tr{'remove'}' />
  <input type='hidden' name='KEY' value='$fingerprint' />
  </form>
  </td>
  </tr>
END
;
    $row++;
  }

  print <<END
</table>
END
;

  Header::closebox();
}


#------------------------------------------------------------------------------
# sub show_contacts()
#
# Outputs the 'Contacts' part of the page.
#
# New contacts can be added and existing ones enabled/disabled or deleted.
#------------------------------------------------------------------------------

sub show_contacts()
{
  my $button          = $Lang::tr{'add'};
  my $current_address = '';
  my $keyid           = '';
  my $enable          = 0;
  my $name            = '';

  Header::openbox('100%', 'left', $Lang::tr{'statusmail contacts'});

  if ($current_contact)
  {
    $button          = $Lang::tr{'update'};
    $name            = clean( $current_address );

    if (exists $contacts{$current_contact})
    {
      $current_address = clean( $contacts{$current_contact}{'email'} );
      $keyid           = $contacts{$current_contact}{'keyid'};
    }
  }

  # Edit contact

  print <<END
  <form method='post' action='$ENV{'SCRIPT_NAME'}'>
    <table width='100%' cellspacing='1'>
      <tr>
        <td width='15%'>$Lang::tr{'statusmail name'}</td>
        <td>
          <input type='text' name='name' value='$name'>
        </td>
        <td>$Lang::tr{'statusmail email'}</td>
        <td>
          <input type='email' name='address' value='$current_address'>
        </td>
      </tr>
      <tr>
        <td>$Lang::tr{'statusmail keyid'}</td>
        <td colspan='3'>
          <select name='keys'>
END
;

  foreach my $key (sort keys %keys)
  {
    my $select = '';
    $select = ' selected' if ($keys{$key}{keyid} eq $keyid);
    print "<option value='$keys{$key}{keyid}'$select>$keys{$key}{keyid}</option>\n";
  }

  print <<END
          </select>
        </td>
      </tr>
    </table>
    <br><hr>
    <table width='100%'>
      <tr>
        <td align='right'><input type='submit' name='CONTACT_ACTION' value='$button'></td>
      </tr>
    </table>
  </form>
  <hr>
  <table width='100%' class='tbl'>
  <tr>
    <th width='25%'>$Lang::tr{'statusmail name'}</th>
    <th width='40%'>$Lang::tr{'statusmail email'}</th>
    <th width='25%'>$Lang::tr{'statusmail key'}</th>
    <th colspan='3'>$Lang::tr{'statusmail action'}</th>
  </tr>
END
;

  # List contacts

  my $row = 0;
  foreach my $contact (sort keys %contacts)
  {
    my $col = '';
    my $gif;
    my $gdesc;
    my $name = clean( $contact );

    if ($current_contact eq $contact)
    {
      print "<tr bgcolor='${Header::colouryellow}'>";
    }
    elsif ($row % 2)
    {
      print "<tr bgcolor='$color{'color20'}'>";
    }
    else
    {
      print "<tr bgcolor='$color{'color22'}'>";
    }

    if ($contacts{$contact}{'enable'} eq 'on')
    {
      $gif = 'on.gif';
      $gdesc = $Lang::tr{'click to disable'};
    }
    else
    {
      $gif = 'off.gif';
      $gdesc = $Lang::tr{'click to enable'};
    }

    print <<END
  <td align='center'>$name</td>
  <td align='center'>$contacts{$contact}{'email'}</td>
  <td align='center'>$contacts{$contact}{'keyid'}</td>

  <td align='center'>
  <form method='post' action='$ENV{'SCRIPT_NAME'}'>
  <input type='hidden' name='CONTACT_ACTION' value='toggle contact' />
  <input type='image' name='$Lang::tr{'remove'}' src='/images/$gif' alt='$gdesc' title='$gdesc' />
  <input type='hidden' name='KEY' value='$name' />
  </form>
  </td>

  <td align='center'>
  <form method='post' action='$ENV{'SCRIPT_NAME'}'>
  <input type='hidden' name='CONTACT_ACTION' value='edit contact' />
  <input type='image' name='$Lang::tr{'edit'}' src='/images/edit.gif' alt='$Lang::tr{'edit'}' title='$Lang::tr{'edit'}' />
  <input type='hidden' name='KEY' value='$name' />
  </form>
  </td>

  <td align='center'>
  <form method='post' action='$ENV{'SCRIPT_NAME'}'>
  <input type='hidden' name='CONTACT_ACTION' value='remove contact' />
  <input type='image' name='$Lang::tr{'remove'}' src='/images/delete.gif' alt='$Lang::tr{'remove'}' title='$Lang::tr{'remove'}' />
  <input type='hidden' name='KEY' value='$name' />
  </form>
  </td>
  </tr>
END
;
    $row++;
  }

  print <<END
</table>
END
;
  Header::closebox();
}


#------------------------------------------------------------------------------
# sub show_schedules()
#
# Outputs the 'Schedules' part of the page.
#------------------------------------------------------------------------------

sub show_schedules()
{
  my $button          = $Lang::tr{'add'};
  my $enable          = 0;
  my %schedule        = ( 'subject' => '',
                          'email'   => '',
                          'format'  => 'HTML',
                          'mday'    => 0,
                          'wday'    => 0,
                          'hours'   => 0,
                          'enable'  => 0 );

  my $name            = clean( $current_schedule );

  Header::openbox('100%', 'left', $Lang::tr{'statusmail schedules'});

  if ($current_schedule)
  {
    $button          = $Lang::tr{'update'};

    foreach my $field ( keys %{ $schedules{$current_schedule} } )
    {
      $schedule{$field} = $schedules{$current_schedule}{$field};
    }
  }

  # Edit schedules

  print <<END
  <form method='post' action='$ENV{'SCRIPT_NAME'}'>
    <table width='100%' cellspacing='1'>
      <tr>
        <td width='15%'>$Lang::tr{'statusmail name'}</td>
        <td colspan='3'>
          <input type='text' name='name' value='$name' size='80'>
        </td>
      </tr>
      <tr>
        <td>$Lang::tr{'statusmail email subject'}</td>
        <td colspan='3'>
          <input type='text' name='subject' value='$schedule{'subject'}' size='80'>
        </td>
      </tr>
      <tr>
        <td>$Lang::tr{'statusmail email to'}</td>
        <td>
          <select name='emails' size='3' multiple>
END
;

  foreach my $contact (sort keys %contacts)
  {
    my $select = '';
    $select    = ' selected' if ($schedule{'email'} =~ m/$contact/);
    my $name   = clean($contact);

    print "<option value='$name'$select>$name</option>\n";
  }

  my $select_html   = $schedule{'format'}      ne 'text'   ? ' selected' : '';
  my $select_text   = $schedule{'format'}      eq 'text'   ? ' selected' : '';
  my $select_hours  = $schedule{'period-unit'} eq 'hours'  ? ' selected' : '';
  my $select_days   = $schedule{'period-unit'} eq 'days'   ? ' selected' : '';
  my $select_weeks  = $schedule{'period-unit'} eq 'weeks'  ? ' selected' : '';
  my $select_months = $schedule{'period-unit'} eq 'months' ? ' selected' : '';

  print <<END
          </select>
        </td>
        <td width='20%'>$Lang::tr{'statusmail email format'}</td>
        <td width='20%'>
          <select name='format' onchange='change_visibility(this)'>
            <option value='html'$select_html>HTML</option>
            <option value='text'$select_text>Text</option>
          </select>
        </td>
      </tr>
      <tr>
      <tr>
        <td width='20%'>$Lang::tr{'statusmail period covered'}:</td>
        <td>
          <input type='number' name='period-value' min='1' max='365' value='$schedule{'period-value'}' pattern='type\\d+'>
          <select name='period-unit' size='1'>
            <option value='hours'$select_hours>$Lang::tr{'hours'}</option>
            <option value='days'$select_days>$Lang::tr{'days'}</option>
            <option value='weeks'$select_weeks>$Lang::tr{'weeks'}</option>
            <option value='months'$select_months>$Lang::tr{'months'}</option>
          </select>
        </td>
        <td>$Lang::tr{'statusmail lines per item'}</td>
        <td>
          <input type='number' name='lines' min='1' max='1000' value='$schedule{'lines'}' pattern='\\d+'>
        </td>
      </tr>
    </table>
    <br>
    <table width='100%' cellspacing='1'>
      <tr>
        <td colspan='31'>$Lang::tr{'statusmail day of month'}:</td>
      </tr>
      <tr>
END
;

  foreach my $day (1..31)
  {
    print "<td align='center'>$day</td>\n";
  }

  print "</tr><tr>\n";

  foreach my $day (1..31)
  {
    my $checked = ($schedule{'mday'} & (1 << $day)) ? ' checked' : '';
    print "<td align='center'><input type='checkbox' name='mday_$day'$checked></td>\n";
  }

  print <<END
      </tr>
      <tr><td colspan='31'>&nbsp;</td></tr>
      <tr>
        <td colspan='31'>$Lang::tr{'statusmail day of week'}:</td>
      </tr>
      <tr>
END
;

 foreach my $day ('sunday', 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday')
  {
    my $wday = "statusmail $day";
    print "<td align='center'>$Lang::tr{$wday}</td>\n";
  }

  print "</tr><tr>\n";

  foreach my $day (0..6)
  {
    my $checked = ($schedule{'wday'} & (1 << $day)) ? ' checked' : '';
    print "<td align='center'><input type='checkbox' name='wday_$day'$checked></td>\n";
  }

  print <<END
      </tr>
      <tr><td colspan='31'>&nbsp;</td></tr>
      <tr>
        <td colspan='31'>$Lang::tr{'statusmail hour of day'}:</td>
      </tr>
END
;

  foreach my $hour (0..23)
  {
    print "<td align='center'>$hour</td>\n";
  }

  print "</tr><tr>\n";

  foreach my $hour (0..23)
  {
    my $checked = ($schedule{'hours'} & (1 << $hour)) ? ' checked' : '';
    print "<td align='center'><input type='checkbox' name='hour_$hour'$checked></td>\n";
  }

  print <<END
      </tr>
    </table>
    <br><hr>

    <script>
      function change_visibility(self)
      {
        var format = self.value;

        var x = document.getElementsByClassName( "html" );
        for ( y = 0 ; y < x.length ; y++ )
        {
          if (format == 'html')
          {
            x[y].removeAttribute( "hidden" );
          }
          else
          {
            x[y].setAttribute( "hidden", "on" );
          }
        }

        var x = document.getElementsByClassName( "text" );
        for ( y = 0 ; y < x.length ; y++ )
        {
           if (format == 'html')
          {
             x[y].removeAttribute( "hidden" );
          }
          else
          {
            x[y].setAttribute( "hidden", "on" );
          }
        }
      }
    </script>

    <table width='100%'>
END
;

  # List items

  foreach my $section (sort keys %items)
  {
    print "<tr style='height:3em'><td colspan='4'><h3>" . clean( $section ) . "</h3></td></tr>\n";

    foreach my $subsection (sort keys %{ $items{$section} } )
    {
      print "<tr style='height:2em'><td colspan='4'><h4 style='padding-left: 20px'>" . clean( $subsection ) . "</h4></td></tr>\n";

      foreach my $item (sort keys %{ $items{$section}{$subsection} } )
      {
        my $name    = $items{$section}{$subsection}{$item}{'ident'};
        my $class   = $items{$section}{$subsection}{$item}{'format'};
        my $hidden  = '';
        my $checked = '';

        if (($class eq 'html' and $schedule{'format'} eq 'text') or
            ($class eq 'text' and $schedule{'format'} eq 'html'))
        {
          $hidden = ' hidden';
        }

        $checked = ' checked' if ($schedule{"enable_${name}"} eq 'on');

        print "<tr class='$class'$hidden><td><span style='padding-left: 40px; line-height: 2.2'>" . clean( $item ) . "</span></td>\n";
        print "<td><input type='checkbox' name='enable_${name}'$checked></td>\n";

        if (exists $items{$section}{$subsection}{$item}{'option'})
        {
          my $key = clean( "value_$name" );

          print "<td>" . clean( $items{$section}{$subsection}{$item}{'option'}{'name'} ) . "</td>\n";

          if ($items{$section}{$subsection}{$item}{'option'}{'type'} eq 'integer')
          {
            my $min   = $items{$section}{$subsection}{$item}{'option'}{'min'};
            my $max   = $items{$section}{$subsection}{$item}{'option'}{'max'};
            my $value = $min;

            $value = $schedule{"value_$name"} if (exists $schedule{"value_$name"});

            print "<td><input type='number' name='$key' min='$min' max='$max' value='$value' pattern='\\d+'></td>\n";
          }
          else
          {
            print "<td><select name='value_$name'>\n";

            my $current = $items{$section}{$subsection}{$item}{'option'}{'values'}[0];

            $current = $schedule{"value_$name"} if (exists $schedule{"value_$name"});

            foreach my $option (@{ $items{$section}{$subsection}{$item}{'option'}{'values'} })
            {
              my ($name, $value) = split /:/, $option;
              $value ||= $name;

              my $select = '';
              $select    = ' selected' if ($current eq $value);

              my $text   = clean( $name );

              print "<option value='$value'$select>$name</option>\n";
            }

            print "</select></td>\n";
          }
        }
        else
        {
          print "<td>&nbsp;</td>\n";
          print "<td>&nbsp;</td>\n";
        }
        print "</tr>\n";
      }
    }
  }

  print <<END
  </table>
    <hr>
    <table width='100%'>
      <tr>
        <td align='right'><input type='submit' name='SCHEDULE_ACTION' value='$button'></td>
      </tr>
    </table>
  </form>
  <hr>
  <table width='100%' class='tbl'>
  <tr>
    <th width='90%'>$Lang::tr{'statusmail name'}</th>
    <th colspan='4'>$Lang::tr{'statusmail action'}</th>
  </tr>
END
;

  # List schedules

  my $row = 0;
  foreach my $schedule (sort keys %schedules)
  {
    my $col = '';
    my $gif;
    my $gdesc;
    my $name = clean( $schedule );

    if ($current_contact eq $name)
    {
      print "<tr bgcolor='${Header::colouryellow}'>";
    }
    elsif ($row % 2)
    {
      print "<tr bgcolor='$color{'color20'}'>";
    }
    else
    {
      print "<tr bgcolor='$color{'color22'}'>";
    }

    if ($schedules{$schedule}{'enable'} eq 'on')
    {
      $gif = 'on.gif';
      $gdesc = $Lang::tr{'click to disable'};
    }
    else
    {
      $gif = 'off.gif';
      $gdesc = $Lang::tr{'click to enable'};
    }

    print <<END
  <td>$name</td>

  <td align='center'>
  <form method='post' action='$ENV{'SCRIPT_NAME'}'>
  <input type='hidden' name='SCHEDULE_ACTION' value='toggle schedule' />
  <input type='image' name='$Lang::tr{'remove'}' src='/images/$gif' alt='$gdesc' title='$gdesc' />
  <input type='hidden' name='KEY' value='$name' />
  </form>
  </td>

  <td align='center'>
  <form method='post' action='$ENV{'SCRIPT_NAME'}'>
  <input type='hidden' name='SCHEDULE_ACTION' value='execute schedule' />
  <input type='image' name='$Lang::tr{'remove'}' src='/images/play.png' '$Lang::tr{'statusmail execute'}' title='$Lang::tr{'statusmail execute'}' />
  <input type='hidden' name='KEY' value='$name' />
  </form>
  </td>

  <td align='center'>
  <form method='post' action='$ENV{'SCRIPT_NAME'}'>
  <input type='hidden' name='SCHEDULE_ACTION' value='edit schedule' />
  <input type='image' name='$Lang::tr{'edit'}' src='/images/edit.gif' alt='$Lang::tr{'edit'}' title='$Lang::tr{'edit'}' />
  <input type='hidden' name='KEY' value='$name' />
  </form>
  </td>

  <td align='center'>
  <form method='post' action='$ENV{'SCRIPT_NAME'}'>
  <input type='hidden' name='SCHEDULE_ACTION' value='remove schedule' />
  <input type='image' name='$Lang::tr{'remove'}' src='/images/delete.gif' alt='$Lang::tr{'remove'}' title='$Lang::tr{'remove'}' />
  <input type='hidden' name='KEY' value='$name' />
  </form>
  </td>
  </tr>
END
;
    $row++;
  }

  print <<END
</table>
END
;
  Header::closebox();
}


#------------------------------------------------------------------------------
# sub check_key( key )
#
# Checks an imported PGP key to see if it looks correct and then tries
# to import it into the the keyring.
#------------------------------------------------------------------------------

sub check_key( $ )
{
  my ($key) = @_;

  $key =~ s/^\s+//;
  $key =~ s/\s+$//;

  # Check it looks like a key

  if ($key !~ m/^-----BEGIN PGP PUBLIC KEY BLOCK-----[A-Za-z\d \/=|\+\n\r-]+-----END PGP PUBLIC KEY BLOCK-----$/)
  {
    $errormessage .= "<p>$Lang::tr{'statusmail invalid key'}</p>";

    return;
  }

  # Looks OK - try to import it

  my ($in, $out, $err);

  my $childpid = open3( $in, $out, $err, "$gpg --import" );

  print $in $key;

  close $in;

  waitpid( $childpid, 0);

  if ($?)
  {
    $errormessage .= join '<br>', "<p>$Lang::tr{'statusmail import key failed'}", <$out>, "</p>\n";
  }
}


#------------------------------------------------------------------------------
# sub get_keys()
#
# Reads the PGP keyring and extracts information on suitable email encryption
# keys.  If a key is found that corresponds to a user not in the contacts list
# the user is added to the contacts. If a key is found for a user in the list
# that does not have a referenced key, the key is added to the contact.
#------------------------------------------------------------------------------

sub get_keys()
{
  %keys = ();

  my @keys = `$gpg --fingerprint --fingerprint --with-colons`;

  my $keyid       = '';
  my $userid      = '';
  my $email       = '';
  my $expires     = 0;
  my $fingerprint = '';
  my $use         = '';

  foreach my $line (@keys)
  {
    my @fields = split /:/, $line;

    if ($fields[0] eq 'pub')
    {
      $keyid       = '';
      $userid      = '';
      $email       = '';
      $expires     = 0;
      $fingerprint = '';
      $use         = '';
    }

    #    0         1       2          3      4              5            6   7      8       9         10
    # type, validity, length, algorithm, keyid, creation date, expiry date, ??, trust, userid, sig class,
    #           11      12    13      14              15     16          17       18      19
    # capabilities, issuer, flag, serial, hash algorithm, curve, compliance, updated, origin

    if (($fields[0] eq 'pub' or $fields[0] eq 'sub')) # and $fields[1] =~ m/e/)
    {
      # Key that can be used for encryption

      $userid  = $fields[9] if ($fields[9]);
      $expires = $fields[6];
      $keyid   = $fields[4];
      $use     = $fields[11];
    }
    elsif ($fields[0] eq 'uid')
    {
      # User id

      $userid = $fields[9];
    }
    elsif ($fields[0] eq 'fpr')
    {
      # Fingerprint

      $fingerprint = $fields[9];
      $fingerprint =~ s/\w{4}\K(?=.)/ /sg;
    }

    if ($keyid and $userid and $expires and $fingerprint and $use =~ m/e/)
    {
      if ($userid =~ m/\@/)
      {
        ($userid, $email) = $userid =~ m/^(.*?)\s+\<(.*)\>/;
      }

      $keys{$fingerprint} = { 'keyid'       => $keyid,
                              'userid'      => $userid,
                              'email'       => $email,
                              'expires'     => $expires,
                              'fingerprint' => $fingerprint };

      if (exists $contacts{$userid} and ($contacts{$userid}{'email'} eq $email or not $contacts{$userid}{'email'}))
      {
        $contacts{$userid}{'email'}       = $email;
        $contacts{$userid}{'keyid'}       = $keyid;
        $contacts{$userid}{'fingerprint'} = $fingerprint;

        $save_contacts = 1;
      }
      elsif (not exists $contacts{$userid})
      {
        $contacts{$userid}{'email'}       = $email;
        $contacts{$userid}{'keyid'}       = $keyid;
        $contacts{$userid}{'fingerprint'} = $fingerprint;
        $contacts{$userid}{'enable'}      = 0;

        $save_contacts = 1;
      }

      $fingerprint   = '';
      $keyid         = '';
    }
  }

  foreach my $contact (keys %contacts)
  {
    if ($contacts{$contact}{'fingerprint'} and not exists $keys{$contacts{$contact}{'fingerprint'}})
    {
      $contacts{$contact}{'fingerprint'} = '';
      $contacts{$contact}{'keyid'}       = '';

      $save_contacts = 1;
    }
  }
}


#------------------------------------------------------------------------------
# sub check_schedule( params )
#
# Checks a schedule is valid
#------------------------------------------------------------------------------

sub check_schedule( % )
{
  my %params = @_;

  my $mdays  = 0;
  my $wdays  = 0;
  my $hours  = 0;
  my $enable = $schedules{$params{'name'}}{'enable'};

  $errormessage .= "<p>$Lang::tr{'statusmail no schedule name'}</p>"   if (not $params{'name'});
  $errormessage .= "<p>$Lang::tr{'statusmail no email subject'}</p>"   if (not $params{'subject'});
  $errormessage .= "<p>$Lang::tr{'statusmail no email addresses'}</p>" if (not $params{'emails'});
  $errormessage .= "<p>$Lang::tr{'statusmail no period covered'}</p>"  if (not $params{'period-value'});
  $errormessage .= "<p>$Lang::tr{'statusmail no lines per item'}</p>"  if (not $params{'lines'});

  foreach my $mday (1..31)
  {
    $mdays |= 1 << $mday if (exists $params{"mday_$mday"});
  }

  foreach my $wday (0..6)
  {
    $wdays |= 1 << $wday if (exists $params{"wday_$wday"});
  }

  foreach my $hour (0..24)
  {
    $hours |= 1 << $hour if (exists $params{"hour_$hour"});
  }

  $errormessage .= "<p>$Lang::tr{'statusmail no schedule date'}" if (not ($mdays+$wdays));
  $errormessage .= "<p>$Lang::tr{'statusmail no schedule time'}" if (not $hours);
  $errormessage .= "<p>$Lang::tr{'statusmail excessive period'}" if (($params{'period-unit'} eq 'hours'  and $params{'period-value'} > (365 * 24)) or
                                                                     ($params{'period-unit'} eq 'days'   and $params{'period-value'} > 365)        or
                                                                     ($params{'period-unit'} eq 'weeks'  and $params{'period-value'} > 52)         or
                                                                     ($params{'period-unit'} eq 'months' and $params{'period-value'} > 12));

  $schedules{$params{'name'}} = { 'subject'      => $params{'subject'},
                                  'email'        => $params{'emails'},
                                  'format'       => $params{'format'},
                                  'period-value' => $params{'period-value'},
                                  'period-unit'  => $params{'period-unit'},
                                  'lines'        => $params{'lines'},
                                  'mday'         => $mdays,
                                  'wday'         => $wdays,
                                  'hours'        => $hours,
                                  'enable'       => $enable };

  foreach my $section (sort keys %items)
  {
    foreach my $subsection (sort keys %{ $items{$section} } )
    {
      foreach my $item (sort keys %{ $items{$section}{$subsection} } )
      {
        my $name   = $items{$section}{$subsection}{$item}{'ident'};
        my $format = $items{$section}{$subsection}{$item}{'format'};

        if (($format eq 'html' and $params{'format'} eq 'text') or
            ($format eq 'text' and $params{'format'} eq 'html'))
        {
          $schedules{$params{'name'}}{"enable_${name}"} = 'off';
        }
        else
        {
          my $state = 'off';

          $state = 'on' if (exists($params{"enable_${name}"}));
          $schedules{$params{'name'}}{"enable_${name}"} = $state;
        }

        if ($items{$section}{$subsection}{$item}{'option'})
        {
          $schedules{$params{'name'}}{"value_${name}"} = $params{"value_${name}"};
        }
      }
    }
  }

  $save_schedules = 1 unless ($errormessage);
}


#------------------------------------------------------------------------------
# sub save_settings( file, hash )
#
# Writes the hash to the named file.  Handles a hash of hashes.
#------------------------------------------------------------------------------

sub save_settings( $$ )
{
  my ($file, $hash) = @_;

  open OUT, '>', $file or die "Can't open $file for output: $!";

  foreach my $item (sort keys %{ $hash })
  {
    print OUT "[$item]\n";

    foreach my $field (sort keys %{ $$hash{$item} })
    {
      print OUT "$field=$$hash{$item}{$field}\n";
    }
  }

  close OUT;
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


#------------------------------------------------------------------------------
# sub addsub add( params )
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
# The function is sanity checked but otherwise ignored by this script.
#------------------------------------------------------------------------------

sub add_mail_item( %)
{
  my %params = @_;


  return unless (exists $params{'section'}    and
                 exists $params{'subsection'} and
                 exists $params{'item'}       and
                 exists $params{'function'});

  if ($params{'format'})
  {
    $params{'format'} = lc $params{'format'};

    return unless ($params{'format'} eq 'html' or
                   $params{'format'} eq 'text' or
                   $params{'format'} eq 'both');
  }
  else
  {
    $params{'format'} = 'both';
  }

  $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}} = { 'format' => $params{'format'},
                                                                         'ident'  => $params{'ident'} };

  if ($params{'option'})
  {
    return unless (ref $params{'option'} eq 'HASH');
    return unless ($params{'option'}{'name'});

    if ($params{'option'}{'type'} eq 'select')
    {
      return unless (ref $params{'option'}{'values'} eq 'ARRAY' and @{ $params{'option'}{'values'} } > 1);

      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'type'}   = $params{'option'}{'type'};
      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'values'} = $params{'option'}{'values'};
      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'name'}   = $params{'option'}{'name'};
    }
    elsif ($params{'option'}{'type'} eq 'integer')
    {
      return unless (exists $params{'option'}{'min'} and exists $params{'option'}{'max'} and $params{'option'}{'min'} < $params{'option'}{'max'});

      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'type'} = $params{'option'}{'type'};
      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'min'}  = $params{'option'}{'min'};
      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'max'}  = $params{'option'}{'max'};
      $items{$params{'section'}}{$params{'subsection'}}{$params{'item'}}{'option'}{'name'} = $params{'option'}{'name'};
    }
  }
}


#------------------------------------------------------------------------------
# sub clean( string )
#
# Converts a string into one that clean in HTML terms.
#------------------------------------------------------------------------------

sub clean( $ )
{
  my ($string) = @_;

  return HTML::Entities::encode_entities( $string );
}


#------------------------------------------------------------------------------
# sub toggle_on_off( string )
#
# Toggles between 'on' and 'off'.
#------------------------------------------------------------------------------

sub toggle_on_off( $ )
{
  $_[0] = $_[0] eq 'on' ? 'off' : 'on';
}


#------------------------------------------------------------------------------
# These functions are referenced by plugins but will not actually be called.
#------------------------------------------------------------------------------


sub get_period_start()
{
}

sub get_period_end()
{
}

sub get_weeks_covered()
{
}

sub cache( $;$ )
{
}
