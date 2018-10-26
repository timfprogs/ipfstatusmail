#! /bin/bash

# Locations of files
settingsdir="/var/ipfire/statusmail"

temp_dir="$TMP"

# Branch to use from repository
branch=master

phase2="no"

if [[ ! -d $settingsdir ]]; then mkdir -p $settingsdir; fi

while getopts ":2hHb:" opt; do
  case $opt in
  2) phase2="yes";;

  b) branch=$OPTARG;;

  :) echo "No argument supplied for option-$OPTARG"; exit 1;;

  *) echo "Usage: $0 [-2]"; exit 1;;
  esac
done

if [[ $phase2 == "no" ]]; then

  # Download the manifest

  wget "https://github.com/timfprogs/ipfstatusmail/raw/$branch/MANIFEST"

  if [[ $? -gt 0 ]]; then echo "Branch $branch not found"; exit 1; fi

  # Download and move files to their destinations

  echo Downloading files

  if [[ ! -r MANIFEST ]]; then
    echo "Can't find MANIFEST file"
    exit 1
  fi

  while read -r name path owner mode || [[ -n "$name" ]]; do
    echo --
    if [[ ! -d $path ]]; then
      echo "Create $name";
      mkdir -p $path;
    fi

    if [[ $name != "." ]]; then
      echo "Download $name";
      wget "https://github.com/timfprogs/ipfstatusmail/raw/$branch/$name" -O $path/$name;
    fi

    echo chown $owner $path/$name
    echo chmod $mode $path/$name
  done < "MANIFEST"

  # Tidy up

  rm MANIFEST

  # Run the second phase of the new install file
  exec $0 -2 -b $branch

  echo Failed to exec $0
fi

echo

# Update language cache

update-lang-cache
