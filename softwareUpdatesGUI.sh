#!/bin/bash
###############################################################################
# Software Updates Wrapper GUI - Release 4 - Generic
# Will Green, October 2016
# Based on work by mm2270: https://github.com/mm2270/CasperSuiteScripts
# Summary: Checks if a Mac has software updates, and if so prompts the user to
#           install them. Supports allowing the user to postpone updates a
#           specificed number of times.
#
# Arguments:
#		1-3 are reserved by JAMF's Casper Suite.
#		4: Max number of times a user may postpone updates
#		5: Logout Mode: set to "--logout" to show a status window while checking for updates, disables restart countdown.
#
#	Exit Codes:
# 	0: Sucessful!
#		1: Generic Error, undefined
#
# Useage:
#	First policy: Run as part of a policy at logout or checkin, as desired.
#               For speed, policy should be scoped to machines with pending
#               updates, rather than all updates.
#
# Do Note:	  This script is made available freely, without any warranty of
#			        any kind. Like any good admin, you should test before deploying
#			        it into any production environment.
###############################################################################
## Enable Logging
logFile="/var/log/swUpdates.log"
log () {
	echo "$1"
	echo "$(date '+%Y-%m-%d %H:%M:%S:') $1" >> "$logFile"
}
log " --> Starting Software Update Wrapper"

## Arguments
postpones=$4			# sets number of times user can postpone updates before forcing updates
mode=$5           # if set to --logout, changes user interaction mode slightly.

## Variables

# Path to CocoaDialog 3 and JAMF's Management Action app
cdPath="/Library/Application Support/JAMF/bin/cocoaDialog.app/Contents/MacOS/cocoaDialog"
mnPath="/Library/Application Support/JAMF/bin/Management Action.app/Contents/MacOS/Management Action"

# path to Software Update Timer file
swuTimerPath="/Library/Application Support/JAMF/.SoftwareUpdateTimer.txt"

# Minutes to count down before doing a restart in non-logout mode
minToRestart=2

# Set Icons to be used
swuIcon="/System/Library/CoreServices/Software Update.app/Contents/Resources/SoftwareUpdate.icns"
restartIcon="/System/Library/CoreServices/loginwindow.app/Contents/Resources/Restart.pdf"

# CocoaDialog Installer Policy Trigger: Called if Cocoa Dialog is missing
cdInstallTrigger="updateJamfBin"

# Get the user current logged in, if any
LoggedInUser=$(who | grep console | awk '{print $1}')

## Checking Varaibles and Arguments
if [[ "$postpones" = "" ]]; then # Were max postpones set?
  log "WARN: Argument 4 (Max Postpones) Not Set. Assuming 5."
  postpones=5
fi

if [[ "$mode" = "--logout" ]]; then # Are we in logout mode
  log "Info: Running in logout mode (Argument 5 set to --logout)"
fi

if [ ! -e "$cdPath" ]; then # Is cocoaDialog missing?
	log "Cocoa Dialog Missing - Triggering updateJamfBin"
	jamf policy -trigger "$cdInstallTrigger"
fi

if [ ! -e "$swuTimerPath" ]; then # Create the timer if it doesn't exist, and get it's value.
	echo "$postpones" > "$swuTimerPath"
fi
Timer=$(cat "$swuTimerPath")

## Functions
fGetUpdatesList () { # Get and process out a list of updates pending
  if [[ "$mode" = "--logout" ]]; then # if called in --logout mode, show progressbar while getting updates
    log "INFO: In logout mode. Opening CocoaDialog..."
    "$cdPath" progressbar --title "Casper Software Update" --text "Checking for macOS updates from Apple..." \
  	--posX "center" --posY 210 --width 450 --float --icon-file "$swuIcon" --indeterminate < /dev/random &
		log "Getting Available Updates..."
    softwareupdate -l > /tmp/SWULIST # Get the updates from software update
  else
    log "Getting Available Updates..."
    softwareupdate -l > /tmp/SWULIST # Get the updates from software update
  fi

  # Process out everything for speed and simplicity
	UpdatesNoRestart=$(cat /tmp/SWULIST | grep recommended | grep -v restart)
	RestartRequired=$(cat /tmp/SWULIST| grep restart | grep -v '\*' | cut -d , -f 1)
	UpdatesList=$(cat /tmp/SWULIST| grep recommended | grep -v '\*' | cut -d , -f 1)

  # Log it all, if it exists
  if [[ "$UpdatesNoRestart" != "" ]]; then
    log "No Restart Updates:
		$UpdatesNoRestart"
  fi

  if [[ "$RestartRequired" != "" ]]; then
    log "Restart Required Updates:
		$RestartRequired"
  fi

  if [[ "$UpdatesList" != "" ]]; then
    log "Reccomended Updates:
		$UpdatesList"
  fi
  # Cleanup CocoaDialog, if present
  if [[ "$mode" = "--logout" ]]; then
    killall cocoaDialog
  fi
}

fUpdatesDone () { # Post-Updates cleanup
	##	Clean up by deleting the SWUList file in /tmp/
	rm /tmp/SWULIST

	##	Let the user know we've finished for 15 seconds...
	"$cdPath" msgbox --title "Casper Software Update" \
	--text "Updates were successfully installed!" --informative-text "Your Mac has been updated, and will now restart." \
	--button1 "   OK   " --icon notice --posY top --width 450 --timeout 15

	##	Delay 1 second, then exit. Force reboot in Logout mode, otherwise hand to UWMA.
	sleep 1
	if [[ "$mode" == "--logout" ]]; then
		reboot
		exit 0
	fi

	## Until We Meet Again...
	fShowRestartProgress ()
	{
	##	Display progress bar
	"$cdPath" progressbar --title "Casper Software Update" --text "Preparing to restart this Mac..."\
	--width 500 --height 90 --icon-file "$restartIcon" --icon-height 48 --icon-width 48 < /tmp/hpipe &

	##	Send progress through the named pipe
	exec 20<> /tmp/hpipe
  }
	##	Close file descriptor 20 if in use, and remove any instance of /tmp/hpipe
	exec 20>&-
	rm -f /tmp/hpipe

	##	Create the name pipe input for the progressbar
	mkfifo /tmp/hpipe
	sleep 0.2

	## Run progress bar sub-function
	fShowRestartProgress

	echo "100" >&20

	timerSeconds=$((minToRestart*60))
	startTime=$( date +"%s" )
	stopTime=$((startTime+timerSeconds))
	secsLeft=$timerSeconds
	progLeft="100"

	while [[ "$secsLeft" -gt 0 ]]; do
		sleep 1
		currTime=$( date +"%s" )
		progLeft=$((secsLeft*100/timerSeconds))
		secsLeft=$((stopTime-currTime))
		minRem=$((secsLeft/60))
		secRem=$((secsLeft%60))
		if [[ $(ps axc | grep "cocoaDialog") == "" ]]; then
			showProgress
		fi
		echo "$progLeft Automatic reboot in: $minRem:$secRem. Please save any open work now." >&20
	done

	echo "Closing progress bar."
	exec 20>&-
	rm -f /tmp/hpipe

	## Close cocoaDialog.
	killall cocoaDialog
  reboot
	exit 0
}

fUpdateInventory () { # Update the inventory in a graphical way
  log "Updating Inventory"
  fShowReconProgress () { #Sub-function to show recon progress

    "$cdPath" progressbar \
    	--indeterminate --title "Casper Software Update" \
    		--icon sync --width 450\
    			--text "Updating Casper Server..." < /tmp/hpipe &
    exec 30<> /tmp/hpipe
  	}

  # Kill any leftover pipes, and make a new one
  exec 30>&-
  rm -f /tmp/hpipe
  mkfifo /tmp/hpipe
  sleep 0.2

  ## Run the install recon sub-function
  fShowReconProgress

  # Run Recon, send progress to pipe
  jamf recon 2>&1 | while read -r line; do
  	##	Re-run the sub-function to display the cocoaDialog window and progress
  	##	if we are not seeing 2 items for CD in the process list
  	if [[ $(ps aux | pgrep "cocoaDialog" | wc -l | sed 's/^ *//') != "1" ]]; then
  		killall cocoaDialog
  		fShowReconProgress
  	fi
  	echo "10 $line" >&30
  done

  # now turn off the progress bar by closing file descriptor 30
  exec 30>&-
  rm -f /tmp/hpipe

  ##	Close all instances of cocoaDialog
  killall cocoaDialog

	## Call Cleanup Function
	fUpdatesDone
}

fRunUpdates () {
  	fShowInstallProgress () { 	#Sub-function to display both a button-less CD window and a progress bar
  	##	Display button-less window above progress bar, push to background. Yes, the weird line formatting below is normal.
  	"$cdPath" msgbox --no-newline --title "Casper Software Update" --text "Installing Software Updates..." --informative-text "Please do not shut down your Mac or put it to sleep until the updates finish installing. This may take several minutes.
Once the updates have been installed, your Mac will automatically restart." --icon-file "$swuIcon" --width 450 --posY top &

  	echo "Displaying progress bar window."
  	"$cdPath" progressbar --title "Casper Software Update" --text "Downloading macOS updates. This may take a few minutes..." \
  	--posX "center" --posY 190 --width 450 --float --icon installer < /tmp/hpipe &
  	exec 10<> /tmp/hpipe
		echo "100 Downloading macOS updates. This may take a few minutes..." >&10
  	}

  exec 10>&- #Setup file discriptor for use in Progress bar
  rm -f /tmp/hpipe
  mkfifo /tmp/hpipe
  sleep 0.2

  # Run the install progress sub-function (shows button-less CD window and progressbar)
  fShowInstallProgress

  #	Run softwareupdate in verbose mode for each selected update, parsing output to feed the progressbar
  #	Set initial index loop value to 0; set initial update count value to 1; set variable for total updates count
  	log "Installing Updates..."
  	softwareupdate --install --recommended --verbose 2>&1 | while read -r line; do
  			##	Re-run the sub-function to display the cocoaDialog window and progress
  			##	if we are not seeing 2 items for CD in the process list
  			if [[ $(ps axc | pgrep "cocoaDialog" | wc -l | sed 's/^ *//') != "2" ]]; then
  				killall cocoaDialog
  				fShowInstallProgress
  			fi
  			pct=$( echo "$line" | awk '/Progress:/{print $NF}' | cut -d% -f1 )
  			echo "$pct Installing macOS Updates..." >&10
  		done

  # Cleanup Progress Bar and CocoaDialog
  exec 10>&-
  rm -f /tmp/hpipe
  killall cocoaDialog

	# Call Recon Function
	fUpdateInventory
}

fMessage-UpdatesAvaialable-Forced () { # Tells the user their postpones are exhausted, and they need to update now.

  log "Postpones have been exhausted. Warning user and Forcing updates."
  "$cdPath" msgbox --no-newline --title "Casper Software Update" --text "Your Mac has updates pending that require a restart." --informative-text "Your Mac is required to install these updates now.

Available Updates:
$UpdatesList

IMPORTANT:
You cannot postpone the updates any longer, and your Mac will restart when they complete.
Save your work now!" --button1 "   OK   " --icon-file "$swuIcon" --timeout 30

  fRunUpdates
}

fMessage-UpdatesAvaialable () { # Dialog and logic for when updates are available, and postpones aren't exhausted.
	# logout mode: Add a timeout timer so that updates run automatically if no one is present.
	if [[ "$mode" == "--logout" ]]; then
		timeout="‑‑timeout 30"
	else
		timeout=""
	fi
	cdResponse=$("$cdPath" msgbox --no-newline --title "Casper Software update" --text "Your Mac has updates pending that require a restart." --informative-text "If you want to install these updates now, click Install. To postpone installing updates to a later time, click Postpone.

Available Updates:
$UpdatesList

You may choose to postpone the updates $Timer more times before your Mac will install them." --button1 "Install" --button2 "Postpone" --icon-file "$swuIcon" "$timeout")
  case $cdResponse in
    "1" )
      fRunUpdates
    ;;
    * )
      let CurrTimer=$Timer-1
      log "User Postponed. Updating Timer file to $CurrTimer and exiting."
      echo "$CurrTimer" > "$swuTimerPath"
      "$mnPath" -title "Software Updates Postponed" \
        -subtitle "We'll ask again tomorrow" \
          -message "You may postpone for $CurrTimer more days"
      exit 0
    ;;
  esac
}

fMessage-UpdatesAvaialable-Lastchance () {
  cdResponse=$("$cdPath" msgbox --no-newline --title "Casper Software Update" --text "Your Mac Has Updates Pending That Requre A Restart" --informative-text "If you want to install these updates now, click Install. To postpone installing updates to a later time, click Postpone.

Available Updates:
$UpdatesList

If you postpone updates again, you WILL be forced to install them and reboot your Mac the next time you are prompted. You will not be able to postpone them again! That could prove be rather inconvenient." --button1 "Install" --button2 "Postpone" --icon-file --timeout 15 "$swuIcon")

case $cdResponse in
    "1" )
      fRunUpdates
    ;;
    * )
      let CurrTimer=$Timer-1
      log "User Postponed. Updating Timer file to $CurrTimer and exiting."
      echo "$CurrTimer" > "$swuTimerPath"
      "$mnPath" -title "Software Updates Postponed" \
          -message "Updates will be forced to install tomorrow - prepare yourself!" \
      exit 0
    ;;
  esac
}

fMessage-UpdatesAvaialable-Logout () { # Dialog and logic for when updates are available at logout.
	cdResponse=$("$cdPath" msgbox --no-newline --title "Casper Software Update" --text "Your Mac Has Updates Pending That Requre A Restart" --informative-text "If you want to install these updates now, click Install. To postpone installing updates to a later time, click Postpone.

Available Updates:
$UpdatesList

You may choose to postpone the updates $Timer more times before your Mac will install them." --button1 "Install" --button2 "Postpone" --timeout "15" --icon-file "$swuIcon")
  case $cdResponse in
    "1" )
      fRunUpdates
    ;;
    * )
      let CurrTimer=$Timer-1
      log "User Postponed. Updating Timer file to $CurrTimer and exiting."
      echo "$CurrTimer" > "$swuTimerPath"
      exit 0
    ;;
  esac
}

## Main Script
fGetUpdatesList # Actually get the updates

# If there are no system updates, quit
if [ "$UpdatesNoRestart" == "" ] && [ "$RestartRequired" == "" ]; then
	log "No updates at this time"
  jamf recon # make sure JAMF knows
	exit 0
fi

#If there is no one logged in, just run the updates
if [ "$LoggedInUser" == "" ] && [ "$mode" != "--logout" ]; then # Check for logout mode to avoid issue with logout mode console user detection
	log "No user logged in, apparently. Running SoftwareUpdate."
	softwareupdate --install --all
  jamf recon # make sure JAMF knows
	exit 0
fi

# If there are only non-restart upates, just install them and notify the user when done.
if [ "$UpdatesNoRestart" != "" ] && [ "$RestartRequired" = "" ]; then
  echo "Only updates do not require restart. Triggering softwareupdate"
  softwareupdate --install --recommended
  # make sure JAMF knows
  jamf recon
  #Notify the user updates happened
  "$mnPath" -title "Updates Installed" -message "IT has updated some software on your Mac. No restart is required."
  exit 0
fi

# If we are here, there are updates that require a restart, and there is a user. So...
case $Timer in
  "0" ) #User has no more postponements available
    fMessage-UpdatesAvaialable-Forced ;;
  "1" ) # User has one postponement leftover
    fMessage-UpdatesAvaialable-Lastchance ;;
  * ) # User has more than 1 postponement left. Prompt for updates.
    fMessage-UpdatesAvaialable ;;
esac

exit 1
