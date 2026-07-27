#!/bin/bash
# Stop the signage player NOW and keep it stopped (survives until start.sh).
# Sync/status/update agents keep running; only the screen is released.
set -u
launchctl unload "$HOME/Library/LaunchAgents/com.farm.signage.plist" 2>/dev/null || true
pkill -f "player.py" 2>/dev/null || true
echo "Signage stopped. Screen is yours. Restart with ./start.sh"
