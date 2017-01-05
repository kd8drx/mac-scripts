#!/bin/bash
###############################################################################
# addLocalAdmin.sh
# Will Davidson, 5 Jan 2016
# Summary: Adds the current console user to the admins group in DSCL
#
# Arguments:
#		1-3 are reserved by JAMF's Casper Suite. 3 is used to get the username
#		4: Manual Mode: Specify -user to enable manual user slection
#   5: username to elevate if manual mode (-user) is set
# Usage:
#	Run it.
# Note:	  This script is made available freely, without any warranty of
#			    any kind. Like any good admin, you should test before deploying
#			    it into any production environment.
###############################################################################
## Check that we are running as sudo/root
if [[ $(whoami) != "root" ]]; then
	echo "FATAL: Script is not running with root privledges! Please run the script with sudo or as root."
	exit 2
fi

## Set Variables
manualMode=$4
userToElevate="$5"

## Define some Functions
fEvalManualMode() {
  if [[ "$userToElevate" == "" ]]; then
    echo "FATAL: Manual mode enabled, but no user to elevate was specified."
    exit 1
  else
    currentUser="$userToElevate"
  fi
}

fEvalAutoMode() {
  currentUser="$(/usr/bin/last -1 -t console | awk '{print $1}')"
}

## Evaluate if Manual Mode is set
case $manualMode in
  "-user" )
    echo "Manual Mode Selected"
    fEvalManualMode;;
  *)
   echo "Auto Mode Selected"
   fEvalAutoMode
esac

## Add user to the admin group
echo "User to elevate is $currentUser"
dseditgroup -o edit -a "$currentUser" -t user admin > /dev/null

## Verify they were added
dseditgroup -o checkmember -m "$currentUser" admin > /dev/null
result="$?"

## Evaluate the result, vomit if it isn't good.
if [[ "$result" -eq 0 ]]; then
  echo "$currentUser was granted local admin rights."
  exit 0
else
  echo "FATAL: dseditgroup exited code $result. $currentUser was probably not granted local admin rights."
  exit 1
fi
