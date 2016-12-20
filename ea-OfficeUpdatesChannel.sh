#!/bin/bash
# EA: Check for what channel Office Updates are on
channel=$(defaults read com.microsoft.autoupdate2 ChannelName)

case "$channel" in
  "InsiderFast")
    echo "<result>Insider Fast</result>";;
  "External")
    echo "<result>Insider Slow</result>";;
  *)
   echo "<result>Production</result>";;
esac
exit 0
