#!/bin/bash
# Proof-of-life: screenshot what the TV is showing + a short status text,
# uploaded to the Drive folder under _status/ (subfolders are never played).
# launchd runs this every 10 minutes. Best-effort: any failure exits quietly.
set -u

# Remote precedence: $SIGNAGE_REMOTE env > ~/.signage-remote file > default.
REMOTE="${SIGNAGE_REMOTE:-}"
[ -z "$REMOTE" ] && [ -f "$HOME/.signage-remote" ] && REMOTE="$(head -1 "$HOME/.signage-remote")"
[ -z "$REMOTE" ] && REMOTE="gdrive:Foyer Signage"
RCLONE="$(command -v rclone || true)"
[ -x "${RCLONE:-/nonexistent}" ] || RCLONE=/usr/local/bin/rclone
[ -x "$RCLONE" ] || exit 0

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

screencapture -x "$TMP/latest.png" 2>/dev/null || exit 0
sips --resampleHeightWidthMax 1200 "$TMP/latest.png" --out "$TMP/latest.png" >/dev/null 2>&1

{
  date "+%F %T"
  uptime
  echo "--- last player log lines ---"
  tail -5 "$HOME/signage.log" 2>/dev/null
} > "$TMP/status.txt"

"$RCLONE" copyto "$TMP/latest.png" "$REMOTE/_status/latest.png" --timeout 60s 2>/dev/null
"$RCLONE" copyto "$TMP/status.txt" "$REMOTE/_status/status.txt" --timeout 60s 2>/dev/null
