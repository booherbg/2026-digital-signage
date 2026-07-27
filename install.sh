#!/bin/bash
# Install the signage player as a launchd agent: starts at login, relaunches
# on crash. Run once from the repo directory: ./install.sh [content-folder]
set -euo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
PLIST="$HOME/Library/LaunchAgents/com.farm.signage.plist"
FOLDER="${1:-}"

# Prefer a python whose Tk is 8.6+ (PNG support, better photo quality);
# fall back to any python3 with tkinter.
# probe() runs a python check with a 10s watchdog — a broken/half-installed
# python (e.g. aborted brew) can hang forever on import otherwise.
probe() {  # $1=python  $2=code
  "$1" -c "$2" 2>/dev/null &
  local pid=$!
  ( sleep 10; kill -9 "$pid" 2>/dev/null ) &
  local watchdog=$!
  wait "$pid" 2>/dev/null
  local rc=$?
  kill "$watchdog" 2>/dev/null
  return $rc
}
PY=""
for cand in /Library/Frameworks/Python.framework/Versions/Current/bin/python3 \
            /usr/local/bin/python3 /opt/homebrew/bin/python3 /usr/bin/python3; do
  [ -x "$cand" ] || continue
  echo "checking $cand ..."
  if probe "$cand" 'import tkinter,sys; sys.exit(0 if tkinter.TkVersion>=8.6 else 1)'; then
    PY="$cand"; break
  fi
  [ -z "$PY" ] && probe "$cand" 'import tkinter' && PY="$cand"
done
: "${PY:=/usr/bin/python3}"
echo "Using python: $PY (Tk $("$PY" -c 'import tkinter;print(tkinter.TkVersion)' 2>/dev/null || echo '?'))"

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.farm.signage</string>
  <key>ProgramArguments</key>
  <array>
    <string>${PY}</string>
    <string>${DIR}/player.py</string>$([ -n "$FOLDER" ] && printf '\n    <string>%s</string>' "$FOLDER")
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key><string>${HOME}/signage.log</string>
  <key>StandardErrorPath</key><string>${HOME}/signage.log</string>
</dict>
</plist>
EOF

launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

# Sync agent: pulls the Drive folder to ~/Signage every 60s via rclone.
# Harmless if rclone isn't set up yet (sync.sh exits quietly).
SYNC_PLIST="$HOME/Library/LaunchAgents/com.farm.signage.sync.plist"
cat > "$SYNC_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.farm.signage.sync</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${DIR}/sync.sh</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>60</integer>
  <key>StandardErrorPath</key><string>${HOME}/signage-sync.log</string>
</dict>
</plist>
EOF
launchctl unload "$SYNC_PLIST" 2>/dev/null || true
launchctl load "$SYNC_PLIST"

# Self-update agent: pulls the latest main from GitHub once a day (no git
# needed — tarball download; see update.sh). Failure never breaks the install.
UPDATE_PLIST="$HOME/Library/LaunchAgents/com.farm.signage.update.plist"
cat > "$UPDATE_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.farm.signage.update</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${DIR}/update.sh</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict><key>Hour</key><integer>4</integer><key>Minute</key><integer>30</integer></dict>
</dict>
</plist>
EOF
launchctl unload "$UPDATE_PLIST" 2>/dev/null || true
launchctl load "$UPDATE_PLIST"

# Status agent: screenshot + heartbeat to Drive _status/ every 10 minutes.
# Wrapped in an .app bundle because TCC won't attribute Screen Recording to a
# bare bash-under-launchd process (silent wallpaper-only screenshots). The
# applet gets a real TCC identity: macOS prompts once, the grant sticks.
STATUS_APP="$HOME/Applications/SignageStatus.app"
mkdir -p "$HOME/Applications"
rm -rf "$STATUS_APP"
osacompile -e "do shell script \"/bin/bash '${DIR}/status.sh'\"" -o "$STATUS_APP"

STATUS_PLIST="$HOME/Library/LaunchAgents/com.farm.signage.status.plist"
cat > "$STATUS_PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.farm.signage.status</string>
  <key>ProgramArguments</key>
  <array>
    <string>${STATUS_APP}/Contents/MacOS/applet</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>600</integer>
</dict>
</plist>
EOF
launchctl unload "$STATUS_PLIST" 2>/dev/null || true
launchctl load "$STATUS_PLIST"

echo "Installed and started. Logs: ~/signage.log, ~/signage-sync.log"
echo "Stop with: launchctl unload $PLIST $SYNC_PLIST"
