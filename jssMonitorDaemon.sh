#!/bin/bash
# JSS Monitor Daemon
# Checks that the JSS is listening on port 8443 or 8080, and restarts it if both are offline.
## Configure Below
serviceName="tomcat8" # Define the name of the service to restart. Usualy jamf.tomcat8 or tomcat8
logFile="/var/log/jssMonitorDaemon.log"

## Slack Settings
enableSlack="true" # true or false. If true, a slack notice will be pushed during a restart.
clientCode="XXX" # Set to client code
instanceManualIP="1.1.1.1" # Set to instance external IP
slackPushEndpoint="https://hooks.slack.com/services/ZXZXZXZXZXZXZXZXZXZXZXZXZXZX" # URL Endpoing to send notice to
instanceName=$(cat /etc/hostname) # Manually set or leave auto to get hostname
instanceReportedIP=$(ip addr | grep 'state UP' -A2 | tail -n1 | awk '{print $2}' | cut -f1  -d'/')  #Manually set or leave auto to get first ipv4 address reported in ip addr.
time=$(date +'%s')

## Slack Message Template - be very careful with escaping quotes here!
slackMessage="{\"attachments\": [
        {
            \"fallback\": \"The JSS Instance on $instanceName ($instanceReportedIP) at $clientCode was reset after becoming unresponsive.\",
            \"color\": \"warning\",
            \"author_name\": \"JSS Auto-Restart Daemon\",
            \"author_icon\": \"https://cdn2.iconfinder.com/data/icons/freecns-cumulus/32/519840-52_Cloud_Sync-128.png\",
            \"title\": \"Automatic JSS Restart Initiated\",
            \"text\": \"A JSS instance has been automatically reset after becoming unresponsive.\",
            \"fields\": [
                {
                    \"title\": \"Client\",
                    \"value\": \"$clientCode\",
                    \"short\": true
                },
				{
                    \"title\": \"Instance Name\",
                    \"value\": \"$instanceName\",
                    \"short\": true
                },
								{
                    \"title\": \"Reported IP\",
                    \"value\": \"$instanceReportedIP\",
                    \"short\": true
                },
                {
                    \"title\": \"Manual IP\",
                    \"value\": \"$instanceManualIP\",
                    \"short\": true
                }
            ],
            \"ts\": \"$time\"
        }
    ]
}"

### Script Guts - don't edit below here
## Functions
log () { # Enable Logging
	echo "$1"
	echo "$(date) ]: $1" >> "$logFile"
}

fSendSlackPush() { # Push to Slack
  curl -X POST -H 'Content-type: application/json' \
  --data "$slackMessage" \
   "$slackPushEndpoint"

  log "Slack Notification Sent to $slackPushEndpoint"
}

fCheckJSSStatus() { # Check JSS Status and restart if need be
  jssStatus=$(netstat -l | grep -c ':8443\|:8080')
    if [[ "$jssStatus" -eq 0 ]]; then
      log "JSS does not appear to be listening on defined ports. Calling a restart."
      service "$serviceName" restart
      didRestart="true"
    else
      log "JSS Status: $jssStatus. Looks ok!"
      didRestart="false"
    fi
}

### Main Runtime
fCheckJSSStatus
if [[ "$enableSlack" == "true" ]] && [[ $"didRestart" == "true" ]]; then
  fSendSlackPush
fi
exit 0
