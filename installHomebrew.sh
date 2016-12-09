#!/bin/bash
###############################################################################
# Homebrew Package Manager Install Wrapper - Release 1 - Generic
# Will Green, June 2016
# Summary: Manually installs Homebrew to a user's home folder, and adds that to
#          their profile's $PATH.
#
# Arguments:
#		1-3 are reserved by JAMF's Casper Suite.
#
# Exit Codes:
#		0: Sucessful!
#		1: Generic Error, undefined
#
###############################################################################
## Variables
currentUser="$(/usr/bin/last -1 -t console | awk '{print $1}')"

## Install Homebrew from GitHub
echo "Installing Homebrew files..."
mkdir "/Users/$currentUser/homebrew"
curl -L https://github.com/Homebrew/brew/tarball/master | tar xz --strip 1 -C "/Users/$currentUser/homebrew"

## Make .bash_profile if it doesn't exist, and set permissions
if [[ ! -e "/Users/$currentUser/.bash_profile" ]]; then
  touch "/Users/$currentUser/.bash_profile"
  chown "$currentUser" "/Users/$currentUser/.bash_profile"
fi

# Add the new homebrew directory to the user's $PATH
echo "Updating PATH..."
echo "export PATH=/Users/$currentUser/homebrew/bin:$PATH" >> "/Users/$currentUser/.bash_profile"

exit 0
