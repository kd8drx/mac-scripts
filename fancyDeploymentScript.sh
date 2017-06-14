#!/bin/bash
###############################################################################
# Deploy Policy GUI Wrapper
# Will Green, June 2017
# Summary: Runs the deploy policy on Casper, with a nice CocoaDialog Box showing
#          the user what is going on.
#
# Arguments:
#		1-3 are reserved by JAMF's Casper Suite.
#		4: Company name
#		5: Welcome text
#		6: enable FileVault? If yes, put 1. Otherwise, no.
#		7: Deployment Trigger
#		8: FV Deployment Trigger
#
# Exit Codes:
#		0: Sucessful!
#		1: Generic Error, undefined
#		2: No FileVault Deployment Trigger (Argument 8) was set, but FielVault was set to deploy.
#		3: No  Deployment trigger was set (Argument 7).
#
# Useage:
#	First policy: Attach to a policy as a script set to run Before. Polices That
#               should run on deploy need to have deploy set as a custom Trigger
#
# Do Note:	  This script is made available freely, without any warranty of
#			        any kind. Like any good admin, you should test before deploying
#			        it into any production environment.
###############################################################################
## Enable Logging
logFile="/var/log/systemDeployment.log"
log () {
	echo "$1"
	echo "$(date '+%Y-%m-%d %H:%M:%S:') $1" >> "$logFile"
}
log " --> Starting System Deployment Wrapper"
## Variables
cdPath="/Library/Application Support/JAMF/bin/cocoaDialog.app/Contents/MacOS/cocoaDialog" # CocoaDialog Path
setupAssistantIcon="/System/Library/CoreServices/Setup Assistant.app/Contents/Resources/Assistant.icns" # Change to the icon you want to show in CocoaDialog
cdInstallTrigger="updateJamfBin" # CocoaDialog Installer Policy Trigger: Called if Cocoa Dialog is missing
## Arguments
companyName="$4"
deployText="$5"
deployFilevault="$6"
deployTrigger="$7"
fvEnableTrigger="$8"

## Error Checking and Processing Arguments
if [ ! -e "$cdPath" ]; then # Is cocoaDialog missing?
	log "Cocoa Dialog Missing - Triggering updateJamfBin"
	jamf policy -trigger "$cdInstallTrigger"
fi

if [ "$companyName" == "" ]; then # Was a company name set?
	log "WARN: No company name (Argument 4) was set. Using Defaults."
	companyName="your new Mac"
fi

if [ "$deployText" == "" ]; then # Was deployment text set?
	log "WARN: No deploy text (Argument 5) was set. Using Defaults."
	deployText="We're getting your Mac ready for use"
fi

if [[ "$deployFilevault" == "" ]]; then
	log "WARN: No FileVault Deployment (Argument 6) prefernece was set. Assuming No."
fi

if [[ "$deployTrigger" == "" ]]; then
	log "FATAL: No  Deployment trigger was set (Argument 7). Exiting."
	exit 3
fi

if [[ "$fvEnableTrigger" == "" ]] && [[ $deployFilevault -eq 1 ]]; then
	log "FATAL: No FileVault Deployment Trigger (Argument 8) was set, but FileVault was set to deploy."
	exit 2
fi

## Functions
fRunDeploy () {
  	fShowInstallProgress () { 	#Sub-function to display both a button-less CD window and a progress bar
  	##	Display button-less window above progress bar, push to background. Yes, the weird line formatting below is normal.
  	"$cdPath" msgbox --no-newline --title "Welcome to $companyName!" --text "$deployText" \
			--informative-text "Do not shut down your Mac or put it to sleep until deployment finishes! If you do, your Mac may not work correctly." \
			--icon-file "$setupAssistantIcon" --width 450 --posY top &
		# Display the progress bar
  	"$cdPath" progressbar --title "Configuration In Progress..." --text "Configuring your Mac..." \
  	--indeterminate --posX "center" --posY 185 --width 450 --float --icon installer < /tmp/hpipe &
  	exec 10<> /tmp/hpipe
  	}

  exec 10>&- #Setup file discriptor for use in Progress bar
  rm -f /tmp/hpipe
  mkfifo /tmp/hpipe
  sleep 0.2

  # Run the install progress sub-function (shows button-less CD window and progressbar)
  fShowInstallProgress

  #	Run deploy script in verbose mode, parsing output to feed the progressbar
	log "Running Deployment Script..."
	jamf policy -trigger "$deployTrigger"  2>&1 | while read -r line; do
		##	Re-run the sub-function to display the cocoaDialog window and progress
		##	if we are not seeing 2 items for CD in the process list
		if [[ $(ps aux | pgrep "cocoaDialog" | wc -l | sed 's/^ *//') != "2" ]]; then
			killall cocoaDialog
			fShowInstallProgress
		fi
		echo "10 $line" >&10
	done

	#	Run standard checkin in verbose mode, parsing output to feed the progressbar
	log "Running Checkin..."
	jamf policy -verbose 2>&1 | while read -r line; do
		##	Re-run the sub-function to display the cocoaDialog window and progress
		##	if we are not seeing 2 items for CD in the process list
		if [[ $(ps aux | pgrep "cocoaDialog" | wc -l | sed 's/^ *//') != "2" ]]; then
			killall cocoaDialog
			fShowInstallProgress
		fi
		echo "10 $line" >&10
	done

  # Cleanup Progress Bar and CocoaDialog
  exec 10>&-
  rm -f /tmp/hpipe
  killall cocoaDialog
}

fDeployFinished () {
	log "Notifying User Deployment is done..."
	if [[ $deployFilevault -eq "1" ]]; then
		"$cdPath" msgbox --title "Welcome to $companyName" \
		--text "Deployment Finished Sucessfully!" --informative-text "Your Mac will now enable FileVault and restart. Once the restart is complete, your Mac will be ready to use." \
		--button1 "   OK   " --icon-file "$setupAssistantIcon" --posY top --width 450 --timeout 30
	else
		"$cdPath" msgbox --title "Welcome to $companyName" \
		--text "Deployment Finished Sucessfully!" --informative-text "Your Mac will now restart. Once the restart is complete, your Mac will be ready to use." \
		--button1 "   OK   " --icon-file "$setupAssistantIcon" --posY top --width 450 --timeout 30
	fi
}

fEnableFileVault () {
	log "Enabling FileVault..."
	jamf policy -event "$fvEnableTrigger" -verbose
}

fCheckConsoleUser () { # Check that the user has actually logged in. Don't run until we do.
	currentUser=$(who | grep console | awk '{print $1}')

	case $currentUser in
		"_mbsetupuser" )
			while [[ $(who | grep console | awk '{print $1}') == "_mbsetupuser" ]]; do
				log "Setup Assistant is still running. Waiting until complete..."
				sleep 10
			done
			;;
		"loginwindow" )
			while [[ $(who | grep console | awk '{print $1}') == "loginwindow" ]]; do
				log "Mac is still at loginwindow. Waiting until first login..."
				sleep 10
			done
		 ;;
		 *)
		  log "$currentUser is logged in. Continuing..."
		 ;;
	esac

}

## Main script
caffeinate -disu & # No sleeping for you!
fCheckConsoleUser
fRunDeploy

if [[ $deployFilevault -eq "1" ]]; then # If FileVault was set to deploy, do so.
		fEnableFileVault
	else
		log "FileVault was not set for deployment. Skiping."
fi

fDeployFinished
log "Script complete!"
exit 0
