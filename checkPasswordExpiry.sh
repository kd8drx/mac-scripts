#!/bin/bash
###############################################################################
# Password Expiration Notifier
# Will Green, 28 August 2015
# Updated: 11 November, 2015, 30 March 2016
# Summary: Checks a local user accounts password age, warns if it is less than
# 		   10 days from expiring, and allows the user to change the password
# 		   via System Preferneces.
#
# Arguments:
#		1-3 are reserved by JAMF's Casper Suite. 3 is used to get the username
#		4: Max password age. If not set, defaults to 90 days
#		5: if set to "-checkin", only sends a push notification
#	Exit Codes
#		0: Sucessful!
#		1: Generic Error, undefined
#		2: Current User not via Argument 3
#
# Useage:
#	First policy: Run once per day on checkin, during the morning (9a-11a)
#	Second policy: Run every checkin, with argument 5 set to "-checkin"
#
# Do Note:	  This script is made available freely, without any warranty of
#			        any kind. Like any good admin, you should test before deploying
#			        it into any production environment.
###############################################################################
## Arguments
	currentUser="$3"		# JAMF tells us who the current user is - need this for DSCL
	if [[ $currentUser = "" ]]; then
		echo "FATAL: Argument 4 (Current user) Not Set. This is a required variable. Exiting."
		exit 2
	fi

	if 	[[ "$4" != "" ]]; then		# We can specify the max password age via variable 4. If we don't assume 90 days
		  maxPasswordAge="$4"
		else
		  echo "WARN: Argument 4 (Max Password Age) Not Set. Defaulting to 90 Days."
		  maxPasswordAge="90"
	fi

	if [[ "$5" == "-checkin" ]]; then	# If -checkin is specified, then only push notifications will be shown
		cautionOnly="true"
		echo "NOTICE: Script is in Checkin Mode"
	else
		cautionOnly="false"
	fi

## Variables
	cdPath="/Library/Application Support/JAMF/bin/cocoaDialog.app/Contents/MacOS/cocoaDialog" # Where is CocoaDialog?
	mnPath="/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action" # Where is Management Action?
	currentDateEpoch=$(date +%s) #Number of seconds since the UNIX Epoch

## Functions
	function getPasswordAge() { # Find the age of the password on the Mac for the currently logged in user
		# To do this, we export the accoutPolicyData from Directory Services to a text file, clean it up
		# so it is a valid plist using grep, and then export the key as a variable.
		# We then do some maths to get the age, and clean up

		# But first, error checking! Does the username have account policy data?
		dscl . -read /Users/"$currentUser" accountPolicyData >> /dev/null
		errorCode="$?"
		if [[ $errorCode != 0 ]]; then
			echo "FATAL: Somthing is wrong with DSCL!"
			echo "The user $currentUser may not exist, have no account policy data, or somthing deep with DSCL has gone sideways."
			exit 3
		fi

		# OK, DSCL works, so lets parse this...
		dscl . -read /Users/"$currentUser" accountPolicyData | sed '1d' > /tmp/accountPolicyData.plist

		# Convert the passwordLastSet from Epoch to Days, and figure out how many days we have
		passwordLastSetEpoch=$(defaults read /tmp/accountPolicyData.plist passwordLastSetTime | cut -c 1-10)
		passwordAge=$(bc <<< "scale = 0; ($currentDateEpoch - $passwordLastSetEpoch)/86400")
		passwordExpirationTime=$(bc <<< "scale = 0; $maxPasswordAge-$passwordAge")
		passwordWarnDays=$(bc <<< "scale = 0; $maxPasswordAge-5")
		passwordCautionDays=$(bc <<< "scale = 0; $maxPasswordAge-10")

		# Clean up
		rm /tmp/accountPolicyData.plist

		echo "Password Age: $passwordAge"
		echo "Expiration: $passwordExpirationTime days"
	}

	function changePassword() {
		/usr/bin/osascript -e 'tell application "System Preferences"
    				activate
    				set the current pane to pane id "com.apple.preferences.users"
				    reveal anchor "passwordPref" of pane id "com.apple.preferences.users"
				    tell application "System Events"
				        tell process "System Preferences"
				            click button "Change Password…" of tab group 1 of window 1
				        end tell
				    end tell
				end tell'
	}

	function userForce() { # Tell the user their password has expired, then open the Password Change Dialog
		"$cdPath" msgbox --title "Your Password Has Expired" --text "Your account password has expired!" \
			--informative-text "You must change your password now using System Preferences to prevent issues with your Mac." \
			--icon stop --float --button1 "Change Password" --string-output --no-newline

		changePassword
		exit 0
	}

	function userWarn() { # Warn the user of their password expiring soon. Let them change it if they want.
		cdResult=$("$cdPath" msgbox --title "Your Password Expires Soon" --text "Your account password expires in $passwordExpirationTime days" \
			--informative-text "You can change your password now via System Preferences, or wait until later. You will be forced to change your password once it expires." \
			--icon info --float --button1 "  OK  " --button2 "Change Password" --string-output --no-newline)
		case $cdResult in
			"  OK  " )
				echo "User Pressed OK. Exiting"
				exit 0 ;;
			"Change Password" )
				echo "User Pressed Change Password. Opening System Preferences and exiting."
				changePassword
				;;

		esac
	}

	function userCaution() { # Caution the user of their password expiring soon, or having actually expired.
		if [[ "$passwordAge" -ge "$maxPasswordAge" ]]; then
			"$mnPath" -title "Password Has Expired" -message "Your password has expired! Please change it immediately in System Preferences."
		else
			"$mnPath" -title "Password Expiration Approaching" -message "Your password expires in $passwordExpirationTime days. You can change it using System Preferences."
		fi
	}

## Main Script
getPasswordAge

# If the script was started with -checkin, and the password is within the notificaion period, then send a push notificaiton and exit.
if [[ "$cautionOnly" == "true" ]] && [[ "$passwordAge" -ge "$passwordCautionDays" ]]; then
	echo "Passsword is in notification period. Sending Push Notification!"
	userCaution
	exit 0
fi

# If the script is running normally, then warn using push notifications or CocoaDialog, depending on how old the password is.
if 	[[ "$passwordAge" -le "$passwordCautionDays" ]]; then
	  echo "Password is not in notification period."
	  exit 0
	elif [[ "$passwordAge" -ge "$maxPasswordAge" ]]; then
	  echo "Password has expired. Notifying user!"
	  userForce
	  exit 0
	elif [[ "$passwordAge" -ge "$passwordWarnDays" ]]; then
	  echo "Password is in Warning period. Notifying user!"
	  userWarn
	  exit 0
	else
	  echo "Password is in Caution period. Notifying user!"
	  userCaution
	  exit 0
fi

exit 1
