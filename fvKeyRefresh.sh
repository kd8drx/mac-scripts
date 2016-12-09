#!/bin/bash
###############################################################################
#
#	FVKeyRefresh.sh
#
# 	Purpose: Recycles and escrows the FV2 Key
#
###	Exit Codes	###
#	0 = Sucessful, or an otherwise non-blocking error. See the log for details.
#	1 = Generic Error. See the log output for details.
#	2 = Not running as Root (or with Sudo)
#	4 = User doesn't have the ability to authenticate to FV2 and needed a key refresh
#	5 = FileVault Key Refresh Failed too many times. Catastrophic Failure! Tokyo is gone!
#	6 = The FV2 key escrow Config Profile is missing.
#	7 = Variables were missing
### Script Arguments ###
#	Arguments 1-3 are reserved by JAMF
#	Argument 4: The UUID of a Configuration Profile that provides FileVeult Key Redirection settings
#	Argument 5: The max number of tries a user gets to retry the key refresh
#	Argument 6: the URL of the JSS, without a trailing slash
#	Argument 7: Are Defferals enabled? Yes, or No.
#	Argument 8: Max Deferrals
###############################################################################
#	BootStrap Logging and Basic Requirements
###############################################################################
# Check that we are running as sudo/root
if [[ $(whoami) != "root" ]]; then
	echo "FATAL: Script is not running with root privledges! Please run the script with sudo or as root."
	exit 2
fi

# Enable Logging
	logFile="/var/log/FVKeyRefresh.log"
	log() {
		echo "$1"
		echo "$(date '+%Y-%m-%d %H:%M:%S:' ) $1" >> $logFile
	}
	#Insert a Log Header so each run is easier to tell apart.
	echo "

	*** Logging Enabled Successfully ***
	Script Start Time: $(date)" >> $logFile
	echo "*** Logging Enabled Sucessflly ***"

# Enable Debug Logging (if desired)
# Debugging is enabled by creating an empty file named .debug in /Library/Application Support/IT
	if [[ -e "/Library/Application Support/JAMF/.debug" ]]; then
		enableDebugging="true"
		log "DEBUG: Debugging Enabled"
		else
		enableDebugging="false"
	fi

	debug() {
	if [[ $enableDebugging == "true" ]]; then
		echo "#### Debug:  $1"
		echo "$(date '+%Y-%m-%d %H:%M:%S: ') #### Debug:  $1">> $logFile
	fi
	}

###############################################################################
# Setup Global Variables and Process Parameters
###############################################################################
log "Setting up Variables..."

#####
# Read in Parameters
#####
mountPoint="$1"
computerName="$2"
userName="$(/usr/bin/stat -f%Su /dev/console)"
FVKeyProfileUUID="$4" #The UUID of a Configuration Profile that provides FileVeult Key Redirection settings
fvKeyRefreshAttemptsMax="$5" #The max number of tries a user gets to retry the key refresh
jssURL="$6" # This is the full URL for your JSS, i.e. https://jss.company.tld:8443 - omit the trailing slash!
defferralEnabled="$7" # Are deferrals enabled? Yes, or No
maxDeferrals="$8" # How mant times can the user defer? Default is 5.
#####
# Paths to various utilities used for user interaction
#####

CDPath="/Library/Application Support/JAMF/bin/cocoaDialog.app/Contents/MacOS/cocoaDialog"
mnPath="/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action"

#####
# Useful global variables
#####

osVersion=$(/usr/bin/sw_vers -productVersion | awk -F. {'print $2'})
serialNumber=$(system_profiler SPHardwareDataType | grep "Serial Number (system)" | cut -c 31-)

#####
# Script SpecificVariables
#####
fvKeyRefreshAttempts=0 # This always starts at 0
FVStatus=$(fdesetup status | grep -c "FileVault is On.")
TimerPath="/Library/Application Support/JAMF/.FV2RefreshTimer"


#####
# LOG ALL THE THINGS!
#####

debug "Variables Set:"
debug "Mountpoint is $mountPoint"
debug "Computer Name is $computerName"
debug "Logged in user is $userName"
debug "OS Version is $osVersion"
debug "Serial Number is $serialNumber"
debug "The FileVault Profile Check will use UUID $FVKeyProfileUUID"
debug "The JSS URL is $jssURL"

###############################################################################
# Check Dependencies
###############################################################################
log "Checking Dependencies..."

#	Where Users and Passwords Verified?	#
#	While user's don't have to be specified, leaving the fields blank will break the check script.

#   Cocoa Dialog Installed?   #
if [[ -e "$CDPath" ]]; then
	log "cocoaDialog is Present"
else
	log "cocoaDialog missing - Calling JAMF to install"
	jamf policy -event updateJamfBin -verbose >> $logFile
fi

if [[ $defferralEnabled == "Yes" ]] && [[ $maxDeferrals == "" ]]; then
	log "WARN: Max Deferrals was not set. Assuming 5."
	maxDeferrals=5
fi

# Sanity check varaibles
sanityVariables=("$mountPoint" "$computerName" "$userName" "$FVKeyProfileUUID" "$fvKeyRefreshAttemptsMax" "$jssURL")
for t in "${sanityVariables[@]}"; do
	if [[ "$t" = "" ]]; then
		log "FATAL: A required script argument is blank. Check the arguments being passed to the script and try again."
		echo "${sanityVariables[@]}"
		exit 7
	fi
done

###############################################################################
# Define Functions
###############################################################################

fvKeyRefresh-Prompt-UserFail() { # Notify the user that they don't appear to have the right permissions to FV2 and Fail.
	"$CDPath" msgbox --title 'FileVault Remediation > Error' \
		--text 'FileVault User Authentication Failed' \
		--informative-text "It looks like FileVault is enabled on your Mac, but your user account isn't authorized to unlock the drive." \
		--button1 " OK " --float --no-show --icon stop
}

fvKeyRefresh-Prompt-ConfigFail() { # Notify the user that their Mac cannot escrow the key correctly, and to contact IT.
	"$CDPath" msgbox --title 'FileVault Remediation > Error' \
		--text 'FileVault Key Escrow Failure' \
		--informative-text "The FileVault recovery key cannot be escrowed in Casper at this time, because of a configuration problem on this Mac. Please ensure your Mac is properly enrolled in Capser, and try again." \
		--button1 " OK " --float --no-show --icon stop
}

fvKeyRefresh-Prompt-Initial() { # Notify the user there is a problem with their FileVault key and explain the refresh process
	cdResponse=$("$CDPath" msgbox --title 'FileVault Remediation' \
		--text 'There is an issue with FileVault on this Mac' \
		--informative-text "FileVault is enabled on your Mac, but the recovery key hasn't been stored in Casper. This means IT can't access or recover your data if there is a problem that keeps your Mac from starting.

To address this issue we'll need to recycle the recovery key, which takes about 3 minutes. If now is a bad time, you may defer until later. Once you run out of deferrals, you will be forced to recycle the key!

Deferrals Remaining: $Timer" \
		--button1 "Recycle Key Now" --button2 "Do It Later" --float --no-show --icon notice)
}

fvKeyRefresh-Prompt-Initial-Forced() { # Notify the user there is a problem with their FileVault key and explain the refresh process
	cdResponse=$("$CDPath" msgbox --title 'FileVault Remediation' \
		--text 'There is an issue with FileVault on this Mac' \
		--informative-text "FileVault is enabled on your Mac, but the recovery key hasn't been stored in Casper. This means IT can't access or recover your data if there is a problem that keeps your Mac from starting.

To address this issue we'll need to recycle the recovery key, which takes about 3 minutes. You must recycle the key now." \
		--button1 "Recycle Key Now" --float --no-show --icon notice)
}

fvKeyRefresh-Prompt-Instructions() { # Notify the user there is a problem with their FileVault key and explain the refresh process
	"$CDPath" msgbox --title 'FileVault Remediation' \
		--text 'You will now be promtped for your password' \
		--informative-text "To recycle the key, we need your FileVault password. We only use this to recycle the key - it is never saved or sent to IT." \
		--button1 " OK " --float --no-show --icon info
}

fvKeyRefresh-Prompt-UserPassword() { # Prompt the user for their password
	FVUserPassword=$("$CDPath" inputbox --informative-text "Enter your FileVault password. This is the password you enter when you power on or restart your Mac." \
		--title "FileVault Remediation > Authentication Required" --button1 "OK" --float --no-show --icon filevault \
		| grep -e '[a-zA-Z\-\.]')	# Beware the Pipe! This runs the CD output through a regex to strip it down to just the password.
}

fvKeyRefresh-Prompt-Success() { # Notify the user everything worked
	"$CDPath" msgbox --title 'FileVault Remediation' \
		--text 'FileVault recovery key recycled!' \
		--informative-text 'The recovery key for this Mac was recycled sucessfully, and has been stored in Casper.' \
		--button1 " WooHoo! " --float --no-show --icon notice
}
fvKeyCheck-Prompt-RefreshFailedTryAgain() {
	"$CDPath" msgbox --title 'FileVault Remediation > Error' \
		--text 'The FileVault recovery key recycle failed' \
		--informative-text "The FileVault recovery key couldn't be recycled, likely because you mistyped your password. Please try again." \
		--button1 " OK " --float --no-show --icon notice
}

fvKeyCheck-Prompt-RefreshFailedFatal() {
	"$CDPath" msgbox --title 'FileVault Remediation > Error' \
		--text 'The FileVault recovery cannot be recycled' \
		--informative-text "The FileVault recovery key couldn't be recycled, likely because you mistyped your password too many times. Please try again later. If you need help, contact IT." \
		--button1 " OK " --float --no-show --icon stop
}

fvCheckPrerequisites() { # Make sure we are able to do what we need to do.
	## Is FV2 actually on
	FVStatus=$(fdesetup status | grep -c "FileVault is On.") ## If FileVault is enabled, this will return 1. If not, 0.
	debug "FileVault Status is $FVStatus"
	if [[ $FVStatus -eq 0 ]]; then
			## FV is Off! Why are we here
			log "FileVault is off - reconing so the JSS knows."
			jamf recon
			exit 0
	fi

	## Can the User Logged in unlock FileVault
		fvUserCheck=$(fdesetup list | grep -c "$userName")
		if [[ "$fvUserCheck" -ge 1 ]]; then
			debug "User is $userName, FVUserCheck was $fvUserCheck"
			log "The user logged in has the ability to unlock FileVault. Continuing..."
		else
			debug "User is $userName, FVUserCheck was $fvUserCheck"
			log "It doesn't look like the user logged in can unlock FileVault. Notifying user and failing."
			fvKeyRefresh-Prompt-UserFail
			exit 4
		fi

	## Are we running OS X Mavericks or later
		if [[ $osVersion -ge 9 ]]; then
			debug "OS Version (minor) is $osVersion"
			log "We're running at least OS X Mavericks. Continuting...."
		else
			debug "OS Version (minor) is $osVersion"
			log "We are running a version of OS X older than 9, so a key refresh won't work. We will not refresh the key."
			return 0
		fi

	## Is a FV Key Redirection Profile present?
		FVKeyProfileStatus=$(profiles -Pv | grep -c "$FVKeyProfileUUID")
		if [[ $FVKeyProfileStatus -ge 1 ]]; then
			debug "FVKeyProfileStatus is $FVKeyProfileStatus"
			log "FV Key Redirection Profile was located! Continuing with the key refresh process..."
		else
			debug "FVKeyProfileStatus is $FVKeyProfileStatus"
			log "FATAL: The FV Key Rediretion Profile is missing. We will not refresh the key."
			fvKeyRefresh-Prompt-ConfigFail
			exit 6
		fi
}

fvUserInformAndDefer () { # Let the user know what's happening, and defer if deferral is enabled
	## First, lets check on deferals...
	if [ ! -e "$TimerPath" ]; then # Create the timer if it doesn't exist, and get it's value.
		echo "$maxDeferrals" > "$TimerPath"
	fi
	Timer=$(cat "$TimerPath")

  if [[ $Timer -le 0 ]]; then # Check the value of the timer, and see if the user can defer or if they have to refresh.
  	fvKeyRefresh-Prompt-Initial-Forced #User has no more deferrals available
	else
		fvKeyRefresh-Prompt-Initial # User has more than 0 deferrals left.
  fi

	if [[ $cdResponse -eq 1 ]]; then # Evaluate the response
		log "User Consented to Key Refresh"
	else
		let CurrTimer=$Timer-1
		log "User Deferred. Updating Timer file to $CurrTimer and exiting."
		echo "$CurrTimer" > "$TimerPath"
		"$mnPath" -title "Key Recycle Deferred" -message "You will be prompted to recycle the FilveValt recovery key again tomorrow"
		exit 0
	fi

	# If we're here, the user has consented to the update. Lets tell them what's happening.
	fvKeyRefresh-Prompt-Instructions
}

fvKeyRefresh() { ### Refreshes the FileVault Key on a machines	###
	debug "Entering kvKeyRefresh with $1"
	funcArguments="$1"

	## Notify the user if this is the first time we've run...
		if [[ $funcArguments == "--First-Time" ]]; then
			fvKeyRefresh-Prompt-InformUser
		fi
	## Prompt the user for their password
		fvKeyRefresh-Prompt-UserPassword

	## Using expect, run FDESetup and refresh the key

		## Show a cocoa dialog so the user knows we are working...
		"$CDPath" progressbar --indeterminate --title "FileVault Remediation" --icon filevault --text "Recycling FileVault Key..." --float --no-show < /dev/random &

		############ WARNING WARNING WARNING ###########
		# When debugging is enabled, Expect logs *everything* it does to the log file. This includes what it's sending to the FDESetup binary.
		# This means that the user's password will be logged to an unencrypted text file on their machine. This is a major security risk!!!
		# Debugging is meant for testing and troubleshooting. It should always be disabled in production.
		################################################

		## Enable verbose output from expect if debugging is on...
		if [[ $enableDebugging == "true" ]]; then
			expectDebugCmd="log_file $logFile
			exp_internal 1
			"
		else
			expectDebugCmd=""
		fi

		expect -c "$expectDebugCmd
		spawn fdesetup changerecovery -personal -verbose
		expect \"Enter a password for '/', or the recovery key:\"
		send {$FVUserPassword}
		send \"\n\"
		expect {
			\"*Error: Unable to unlock FileVault.*\" {
				puts \"Error: Unable to unlock FileVault\"
				exit 1
				}
			\"*New*recovery key*\" {
				puts \"New Recovery Key Generated\"
				exit 0
				}
			default {
				puts \"Unknown Result: Check the logs for details\"
				exit 2
			}
		}
		exit 3
		"

	fvKeyRefreshResult=$?
	debug "FDESetup Exit Code was $fvKeyRefreshResult"

	if [[ $fvKeyRefreshResult -eq 0 ]]; then
		log "Key Refresh Sucessful! Escrowing the key..."
		## Manually run FDERecoveryAgent for 11 seoonds, which gives it about two tries to submit the key.
		/usr/libexec/FDERecoveryAgent -LaunchDCheckin 1 & sleep 11
		## kill both it AND the cocoaDialog that is showing refresh status
		killall FDERecoveryAgent
		killall cocoaDialog

		## Tell the user everything worked!
		fvKeyRefresh-Prompt-Success
		return 0
	else
		## Somthing didn't go right! Return to the Key Check function with a non-zero code after killing CocoaDialog
		killall cocoaDialog
		debug "Key Refresh Failed!"
		debug "Key Refresh Attempts was $fvKeyRefreshAttempts"
		fvKeyRefreshAttempts=$((fvKeyRefreshAttempts + 1))
		return 1
	fi
}

###############################################################################
# Main Script Runtime
###############################################################################
# Make sure that we meet all the prereqs
fvCheckPrerequisites

# Inform the user, and process deferments if enabled
if [[ $defferralEnabled == "Yes" ]]; then
	fvUserInformAndDefer
else
	fvKeyRefresh-Prompt-Initial-Forced
	fvKeyRefresh-Prompt-Instructions
fi


# Call the actual key refresh function
fvKeyRefresh

## How did it go?
if [[ $fvKeyRefreshResult -eq 0 ]]; then # It worked - or at least Expect exited with an exit code of 0.
	log "The FileVault key refresh worked! Have a good day."
	rm "$TimerPath" # Remove the timer so they don't get pinged again.
	exit 0
fi
while [[ $fvKeyRefreshResult -gt 0 ]]; do # Looks like it failed, so we'll try again a few times.
	# Evaluate the amount of attempts to see how this goes....
	if [[ $fvKeyRefreshAttempts -le $fvKeyRefreshAttemptsMax ]]; then
		# Tell the log it failed:
		log "Key refresh failed $fvKeyRefreshAttempts time(s). Retrying."
		fvKeyCheck-Prompt-RefreshFailedTryAgain

		# And then call the function again:
		fvKeyRefresh  --retry
	else
		#We've tried too many times. Fail out fatally.
		log "FATAL: fvKeyRefresh has failed too many times. Notifying user and exiting..."
		if [[ $defferralEnabled == "Yes" ]]; then	let CurrTimer=$Timer-1; echo "$CurrTimer" > "$TimerPath"; log "Timer Updated"; fi
		fvKeyCheck-Prompt-RefreshFailedFatal
		exit 5
	fi
done
exit 1 # If we're here, somthing went wrong.
