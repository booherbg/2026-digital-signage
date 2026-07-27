#!/bin/bash
# Restart the signage player after ./stop.sh.
set -u
launchctl load "$HOME/Library/LaunchAgents/com.farm.signage.plist"
echo "Signage running."
