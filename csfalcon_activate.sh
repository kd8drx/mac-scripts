#!/bin/bash 
#----------------------------------------------------------------------------/*
## Crowdstrike Falcon Activation Script (csfalcon_activate.sh)
## Scripts the activation and securing of a Crowdstrike Falcon agent install
## on macOS. While activating the agent is easily scripted, securing the
## installation from unauthorized removal (InstallGuard) is not as it doesn't
## accept password input from stdin (or, if it does, it's entirely 
## undocumented). This script includes an `expect` section that overcomes this,
## allowing MacAdmins to easily deploy Falcon with aumated client management
## tools such as JAMF or Munki.
##
## Variables:
## (1-3 are reserved by JAMFpro)
## 4: Customer ID Checksum (CID)
## 5: Enable Password Protection (1|0)
## 6: Password, if Variable 5 is "1"
##
## Usage:
## Provide the CID and, if desired, a password to enable password protection.
## Run after installing the deployment package.
#----------------------------------------------------------------------------/*
## Static Variables
falconctl="/Library/CS/falconctl"

## Sanity checks + define argument variables
if [[ $(whoami) != "root" ]]; then # I need Sudo
	echo "FATAL: Script is not running with elevated privilege! Please run the script with sudo or as root."
	exit 1
fi

if [[ $4 == "" ]] ## Check CSID
then
    echo "FATAL: No CSID Provided."
    exit 1
    else
        csid="$4"
fi

if [[ $5 -ne "1" ]] && [[ $5 -ne "0" ]] ## Check Password
then
    echo "FATAL: Password Protection State Not Defined."
    exit 1
    else
    installGuard="$5"
fi

if [[ $5 -eq "1" ]] && [[ $6 == "" ]] ## Check that a password is set for InstallGuard, if needed
then
    echo "FATAL: Password Protection enabled, but no password defined."
    exit 1
    else
    password="$6"
fi

## Define how to do the things
function activateFalcon # Pass CSID to falconctl to enable it
{
    $falconctl --verbose license "$csid"
    exitCode="$?"
    #if [[ $exitCode -gt 0 ]] 
    #then
    #    exit $exitCode
    #fi
}

function enableInstallGuard # Script interaction with falcontrl to enable InstallGuard
{
    expect -c "spawn $falconctl --verbose installguard
    expect \"*Falcon Password:*\"
    send {$password}
    send \"\n\"
    expect \"*Confirm Falcon Password:*\"
    send {$password}
    send \"\n\"
    expect {
        \"*Success: InstallGuard is enabled*\" {
            exit 0
        }
        default {
            puts \"Unexpected result in enableInstallGuard() - keep calm and review log output\"
            exit 1
        }
    }"
}
## Do the things
case $installGuard in
    1) echo "Activating Falcon..."
       activateFalcon
       echo "Enabling InstallGuard..."
       enableInstallGuard
    ;;
    0) echo "Activating Falcon..."
       activateFalcon
    ;;
    *) echo "How did we get here?!?"
       exit 1
    ;;
esac
echo "Done! (Probably.)"
