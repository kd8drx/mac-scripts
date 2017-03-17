#!/bin/bash
###############################################################################
# DEP deploy policy GUI Wrapper - Release 5 - Generic
# Will Green, June 2016
# Summary: Runs the deploy policy on Casper, with a nice Progress showing
#          the user what is going on. Designed for DEP.
#
# Arguments:
#		1-3 are reserved by JAMF's Casper Suite.
#		4: enable FileVault? If yes, put 1. Otherwise, no.
#		5: Deployment Trigger
#		6: FV Deployment Trigger
#		7: Optional custom stage trigger, which runs between First and Second default stages. If none, enter "none"
#		8: Optional name for a blank receipt file to be made at the end of deployment in the JAMF Receipts store
#
# Exit Codes:
#		0: Sucessful!
#		1: Generic Error, undefined
#		2: No FileVault Deployment Trigger (Argument 6) was set, but FielVault was set to deploy.
#		3: No Deployment trigger was set (Argument 5).
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
	echo "$(date) ]: $1" >> "$logFile"
}
log " --> Starting DEP Deployment Wrapper"

## Enable Debugging: Set the varible below to 1 to enable
enableDebug="0"

if [[ $enableDebug -eq 1 ]]; then
	set -x
	logFile="/var/log/systemDeployment_DEBUG.log"
	log "#################################"
	log "####### Debugging Enabled: $(date)"
	log "#################################"
fi

## Arguments
enableFilevault="$4"
deployTrigger="$5"
fvEnableTrigger="$6"
customTrigger="$7"
receiptName="$8"

## Variables
cdPath="/Library/Application Support/JAMF/bin/cocoaDialog.app/Contents/MacOS/cocoaDialog" # CocoaDialog Path
psPath="/Library/Application Support/JAMF/bin/System Deployment Monitor.app/Contents/MacOS/System Deployment Monitor"
resourceInstallTrigger="updateJamfBin" # Resource Install Trigger: Called if script resource apps (CocoaDialog and SDM) are missing

## Error Checking and Processing Arguments
if [[ ! -e "$cdPath" ]] || [[ ! -e "$psPath" ]]; then # are Resource Apps missing?
	log "Resource Apps Missing - Triggering $resourceInstallTrigger"
	#Display a dialog so the user doesn't do anything right away...
	osascript -e 'display dialog "\nPreparing to configure your Mac – Please Wait..." buttons "●●▶︎" with title "Preparing for DEP Deployment" with icon file "System:Library:CoreServices:Setup Assistant.app:Contents:Resources:Assistant.icns"' >> /dev/null &
	jamf policy -trigger "$resourceInstallTrigger"
	killall osascript &>/dev/null
fi

if [[ "$enableFilevault" == "" ]]; then
	log "WARN: No FileVault Deployment (Argument 4) prefernece was set. Assuming No."
fi

if [[ "$deployTrigger" == "" ]]; then
	log "FATAL: No  Deployment trigger was set (Argument 5). Exiting."
	exit 3
fi

if [[ "$fvEnableTrigger" == "" ]] && [[ $enableFilevault -eq 1 ]]; then
	log "FATAL: No FileVault Deployment Trigger (Argument 6) was set, but FileVault was set to deploy."
	exit 2
fi

if [[ "$customTrigger" != "" ]] && [[ "$customTrigger" != "none" ]]; then
	log "Custom Trigger ($customTrigger) has been set. Custom stage enabled."
	customStage=1
fi

if [[ $receiptName != "" ]]; then
	log "Custom Receipt Path of $receiptName provided. Receipt will be dropped."
	customReceipt=1
fi

## Functions
fTellPS () { # Sends an Apple Script Call to Progress Screen. Arg 1 is the Variable to set (e.g. htmlURL), Arg 2 is the value (e.g. http://google.com)
	if [[ $1 != "stage" ]]; then
		osascript <<-EOD
		tell application "System Deployment Monitor"
			set $1 of every configuration to $2
			end tell
		EOD
		log "System Deployment Monitor (Config): Set $1 to $2"
	else
		osascript <<-EOD
		tell application "System Deployment Monitor"
		set htmlURL of every configuration to "file:///Library/Application%20Support/JAMF/bin/System%20Deployment%20Monitor.app/Contents/Resources/$2.html"
		end tell
		EOD
		log "System Deployment Monitor (htmlURL): Set $1 to $2"
	fi

}

fShowInstallProgress () { 	#Sub-function to display Progress Screen
"$psPath" &
sleep 5
}

fRunDeploy () {
  #	Default Stage 1
	log "Starting Casper Deployment..."
	fTellPS stage startDeploy
	jamf policy -event "$deployTrigger" 2>&1 | while read -r line; do
		##	Re-run the sub-function to display the Progress Screen window and check
		##	if we are not seeing 1 items for Progress Screen in the process list
		if [[ $(ps aux | pgrep "System Deployment Monitor" | wc -l | sed 's/^ *//') != "1" ]]; then
			killall "System Deployment Monitor"
			fShowInstallProgress
			fTellPS stage startDeploy
		fi
		echo "$line" >> $logFile
	done

	# Optional Custom Stage
	# If the right argument is provided, this stage will run before Stage 2.
	if [[ $customStage -eq 1 ]]; then
		fTellPS stage "$customTrigger" # update HTML GUI
		log "Running Deployment Stage: $customTrigger..."
		jamf policy -event "$customTrigger" 2>&1 | while read -r line; do
			##	Re-run the sub-function to display the Progress Screen window and check
			##	if we are not seeing 1 items for Progress Screen in the process list
			if [[ $(ps aux | pgrep "System Deployment Monitor" | wc -l | sed 's/^ *//') != "1" ]]; then
				killall "System Deployment Monitor"
				fShowInstallProgress
				fTellPS stage "$customTrigger"
			fi
			echo "$line" >> $logFile
		done
	fi

	# Default Stage 2
	fTellPS stage stage2 # update HTML GUI
	fTellPS currentTime 1490 # Move timer bar to ~66%
	log "Running Casper check-in policies..."
	jamf policy 2>&1 | while read -r line; do
		##	Re-run the sub-function to display the Progress Screen window and check
		##	if we are not seeing 1 items for Progress Screen in the process list
		if [[ $(ps aux | pgrep "System Deployment Monitor" | wc -l | sed 's/^ *//') != "1" ]]; then
			killall "System Deployment Monitor"
			fShowInstallProgress
			fTellPS stage stage2
		fi
		echo "$line" >> $logFile
	done
}

fDeployFinished () {
	# If a custom recept name was provied, drop it in JAMF Receipts.
	if [[ $customReceipt -eq 1 ]]; then
		log "Dropping receipt at /Library/Application Support/JAMF/Receipts/$receiptName"
		touch "/Library/Application Support/JAMF/Receipts/$receiptName"
	fi

	# Update HTML
	fTellPS stage reboot
	log "Deployment is complete. Yay!"

	# Next Casper will recon and reboot. This takes about 30 sec, so we'll configure Progress Screen to match
	fTellPS currentTime 0
	fTellPS buildTime 30
	log "Preparing to Restart..."
}

fEnableFileVault () {
	log "Enabling FileVault..."
	fTellPS stage fileVault
	fTellPS currentTime 1820
	jamf policy -event "$fvEnableTrigger"
	sleep 10 # ensure the Mac has time to escrow the key
}

## Main script
log "Reticulating Splines..."
fShowInstallProgress
fTellPS buildTime 2000 # Tell Progress Screen how many seconds you expect this to take. 2000 seconds = ~30 minutes
caffeinate -disu & # No sleeping for you!
fRunDeploy # Run Main Deployment Runtime

# If FileVault was set to deploy, do so.
if [[ $enableFilevault -eq "1" ]]; then
		fEnableFileVault
	else
		log "FileVault was not set for deployment. Skiping."
fi

fDeployFinished
exit 0
