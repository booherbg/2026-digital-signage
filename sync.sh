#!/bin/bash
# One rclone sync pass: Google Drive folder -> local ~/Signage.
# launchd runs this every 60s (see install.sh). Safe by design: if the
# remote is unreachable we touch nothing and the player keeps showing the
# last synced content.
set -u

# Remote precedence: $SIGNAGE_REMOTE env > ~/.signage-remote file > default.
REMOTE="${SIGNAGE_REMOTE:-}"
[ -z "$REMOTE" ] && [ -f "$HOME/.signage-remote" ] && REMOTE="$(head -1 "$HOME/.signage-remote")"
[ -z "$REMOTE" ] && REMOTE="gdrive:Foyer Signage"
DEST="${SIGNAGE_DEST:-$HOME/Signage}"
LOG="$HOME/signage-sync.log"

RCLONE="$(command -v rclone || true)"
[ -x "${RCLONE:-/nonexistent}" ] || RCLONE=/usr/local/bin/rclone
[ -x "$RCLONE" ] || exit 0

mkdir -p "$DEST"
if [ -f "$LOG" ] && [ "$(stat -f%z "$LOG")" -gt 1000000 ]; then
  mv "$LOG" "$LOG.1"
fi

# Only sync when the remote answers; a failed listing (offline, auth blip,
# API hiccup) must never delete local content.
if "$RCLONE" lsf "$REMOTE" --timeout 30s >/dev/null 2>>"$LOG"; then
  "$RCLONE" sync "$REMOTE" "$DEST" --timeout 120s --contimeout 15s \
    --exclude ".*" --quiet 2>>"$LOG" \
    || echo "$(date '+%F %T') sync failed (kept local content)" >>"$LOG"
else
  echo "$(date '+%F %T') remote unreachable, keeping local content" >>"$LOG"
fi
