#! /bin/bash

# Locations of files
settingsdir="/var/ipfire/statusmail"

temp_dir="$TMP"

# Branch to use from repository
branch=master

# Default version
VERSION=0

phase2="no"

if [[ ! -d $settingsdir ]]; then mkdir -p $settingsdir; fi

while getopts ":2hH" opt; do
  case $opt in
  2) phase2="yes";;

  *) echo "Usage: $0 [-2]"; exit 1;;
  esac
done

if [[ $phase2 == "no" ]]; then
  # Check to see if there's a new version available

  echo Check for new version

  wget "https://github.com/timfprogs/ipfstatusmail/raw/$branch/VERSION"

  NEW_VERSION=`cat VERSION`
  rm VERSION

  # Set phase2 to yes to stop download of update

  if [[ $VERSION -eq $NEW_VERSION ]]; then
    phase2="yes"
  fi
fi

if [[ $phase2 == "no" ]]; then

  # Download the manifest

  wget "https://github.com/timfprogs/ipfstatusmail/raw/$branch/MANIFEST"

  # Download and move files to their destinations

  echo Downloading files

  if [[ ! -r MANIFEST ]]; then
    echo "Can't find MANIFEST file"
    exit 1
  fi

  while read -r name path owner mode || [[ -n "$name" ]]; do
    echo --
    echo Download $name
    if [[ ! -d $path ]]; then mkdir -p $path; fi
    if [[ $name != "." ]]; then wget "https://github.com/timfprogs/ipfstatusmail/raw/$branch/$name" -O $path/$name; fi
    chown $owner $path/$name
    chmod $mode $path/$name
  done < "MANIFEST"

  # Tidy up

  rm MANIFEST

  # Run the second phase of the new install file
  exec $0 -2

  echo Failed to exec $0
fi

# Update language cache

update-lang-cache
