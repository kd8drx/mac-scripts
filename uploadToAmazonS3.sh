#!/bin/bash
###############################################################################
#
#	amazonS3Upload.sh
#
# 	Purpose: Grabs the System log (system.0.log.gz) and upload it to Amazon S3
#
#	Author: Will Green
#   2016 Mann Consulting
#
###	Exit Codes	###
#	0 = Sucessful
#	1 = Generic Error. See the log output for details.
# 2 = Sanity check failed! See log, check variables.
# 3 = File to upload does not exist!
### Script Arguments ###
#  All of these are configured below, under Variables.
#  You can choose to use script arguments by specifying the usual $1, $2, etc.
#  We do a sanity check before running to make sure everything is set right.
###############################################################################
#	BootStrap Logging
###############################################################################
# Enable Logging
logFile="/var/log/amazonS3uploader.log"
log () {
	echo "$1"
	echo "$(date '+%Y-%m-%d %H:%M:%S:') $1" >> "$logFile"
}
log " --> Starting Amazon S3 File Upload"
###############################################################################
# Variables -> CONFIGURE THESE BEFORE RUNNING
###############################################################################
# Amazon S3 settings
# Think hard before storing a key or secret here. You can always pass them as arguments.
s3key="$4" # KEY GOES HERE! Enter "$1" to use arguments.
s3secret="$5" #SECRET GOES HERE! Enter "$2" to use arguments.
s3bucket="$6"  # You must provide the bucket name here!
s3endpoint="s3" # this is usually "s3", but in some instances you need a different endpoint.
s3UploadPath="/" # Folder path to put the files in, on the S3 bucket. At a minumum, this must be '/'.
SerialNumber=${system_profiler SPHardwareDataType | grep 'Serial Number (system)' | awk '{print $NF}'}

# File Upload Settings
pathToUpload="/var/log/system.log.0.gz" # Full path and name of file to upload.
filePrefix="$SerialNumber-$(date +%Y-%m-%d-)" #If you don't want a prefix, just make this blank.

###############################################################################
############## Main Script - Don't edit anything below this! ##################
###############################################################################
if [[ $s3key == "" ]]; then
	log "FATAL: No S3 Key provided."
	exit 1
fi

if [[ $s3secret == "" ]]; then
	log "FATAL: No S3 Secret provided."
	exit 1
fi

if [[ $s3bucket == "" ]]; then
	log "FATAL: No S3 Bucket provided."
	exit 1
fi

if [[ $s3UploadPath == "" ]]; then
	log "FATAL: No S3 Upload Path provided."
	exit 1
fi

if [[ $pathToUpload == "" ]]; then
	log "FATAL: No file to upload provided."
	exit 1
fi

#### Functions go here...
function putS3 { # Hat Tip: https://gist.github.com/chrismdp/6c6b6c825b07f680e710
  path="/tmp"
  file="$filenameToUpload"
  aws_path="$s3UploadPath"
  bucket="$s3bucket"
  date=$(date +"%a, %d %b %Y %T %z")
  acl="x-amz-acl:public-read"
  content_type='application/x-compressed-tar'
  string="PUT\n\n$content_type\n$date\n$acl\n/$bucket$aws_path$file"
  signature=$(echo -en "${string}" | openssl sha1 -hmac "${s3secret}" -binary | base64)
  curl -X PUT -T "$path/$file" \
    -H "Host: $bucket.s3.amazonaws.com" \
    -H "Date: $date" \
    -H "Content-Type: $content_type" \
    -H "$acl" \
    -H "Authorization: AWS ${s3key}:$signature" \
    "https://$bucket.$s3endpoint.amazonaws.com$aws_path$file" \
		>> log
}
#### OK, Let's go!
# Strip the file to be uploaded from it's path
fileBasename=$(basename "$pathToUpload")
filenameToUpload="$filePrefix$fileBasename"
log "Copying file \"$fileBasename\"to /tmp for S3 upload."

# Copy the file to /tmp with a date prefix. If the file doesn't exist, die a horrible death. Or, just exit with code 2.
if [[ -e "$pathToUpload" ]]; then
		cp "$pathToUpload" "/tmp/$filenameToUpload"
	else
		log "FATAL: $pathToUpload does not exist. There is no spoon."
		exit 3
fi

# Upload the file to Amazon!
log "Sending /tmp/$filenameToUpload to Amazon S3: https://$s3bucket.$s3endpoint.amazonaws.com$s3UploadPath$filenameToUpload"
putS3 #go baby go!
uploadResult=$? #get the exit code
log "CURL Upload Result: $uploadResult" #tell us said exit code
#cleanup
log "Cleaning up..."
rm "/tmp/$filenameToUpload"

log "Done!
"
exit 0 # Goodbye
