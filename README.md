# ipfstatusmail
Status emails for IPFire

Provides a service to send emails containing information about the status of an IPFire installation.  The contents of the emails
and the schedule that they are sent on can be defined on a WUI.  The emails can be encrypted with GPG.

The encrypted emails can be decrypted with Thunderbird + Enigmail on Linux and K-9 Mail + OpenKeychain on Android.  Other clients
haven't been tested.

## To install

1. Download the installer:

  ```wget https://github.com/timfprogs/ipfstatusmail/raw/master/install-statusmail.sh```
 
2. Make it executable:

  ```chmod +x install-statusmail.sh```

3. Run the installer:

  ```./install-statusmail.sh```

The installer will download the files and install them in the correct places.  You can now go to the WUI (under 'IPFire') and
configure the addon.

## Configuration

1. Create a signing key by clicking on the 'Generate' button.

2. If necessary, create an encryption key in your email client.  You can use an existing key.

3. Import the signing key into your email client.

4. Export the encryption public key from your email client and paste it into the Encryption Key box.  Click on the 'Import' button.
The key will be imported and shown in the list of installed keys.  It will also be added to the the list of contacts.  Repeat as
necessary for additional enryption keys.

5. It is possible to add additional contacts without encryption keys.  This is not recommended for security reasons.

6. Enable the contacts by clicking on the checkbox against the contact's details.  Disabling contacts allows emails to be
stopped from going to a person during holidays while still allowing other people to continue to receive emails.

7. Create schedules.  Each schedule defines the contents of an email message that is sent to one or more contacts, the schedule
for sending the message, and the type of the message.

  - **Name** Schedule name.  Used in the list of schedules.
  - **Email subject** The subject field in the email.
  - **Send email to** The recipients of the email.  Multiple recipients can be selected.
  - **Email format** Text or HTML.  The items available to be sent in the email may differ.
  - **Period covered** Defines the period of data contained in the email.  Not all items use these fields.
  - **Lines per item** Limits the number of lines of data contained in a single item.  Not all items use this field.
  - **Days of Month** and **Days of Week** Defines the days that the email will be sent.  Only one of these options needs to
  be set - they are OR'd together.  At least one checkbox must be selected from these two sets.
  - **Hours** Defines the time of day that the email will be sent.  At least one checkbox must be selected.
  
    The remaining fields define the contents of the email.
  
8. Enable the schedule.
  
