#!/bin/bash
# Proof-of-life: screenshot what the TV is showing + a short status text,
# uploaded to the Drive folder under _status/ (subfolders are never played).
# launchd runs this every 60 seconds. Best-effort: any failure exits quietly.
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

# Screenshot is best-effort: TCC denial must not stop the other uploads.
# Two filenames = screencapture writes one per display (extra name is
# ignored on single-display setups, e.g. clamshell).
SHOT=""
if screencapture -x "$TMP/latest.png" "$TMP/latest2.png" 2>/dev/null && [ -s "$TMP/latest.png" ]; then
  sips --resampleHeightWidthMax 1200 "$TMP/latest.png" --out "$TMP/latest.png" >/dev/null 2>&1
  [ -s "$TMP/latest2.png" ] && sips --resampleHeightWidthMax 1200 "$TMP/latest2.png" --out "$TMP/latest2.png" >/dev/null 2>&1
  SHOT="yes"
fi

NOW="$(cat "$HOME/.signage-nowplaying" 2>/dev/null || true)"
{
  date "+%F %T"
  uptime
  echo "now playing: ${NOW:-unknown}"
  echo "screenshot: ${SHOT:-FAILED (screen recording permission?)}"
  echo "--- last player log lines ---"
  tail -5 "$HOME/signage.log" 2>/dev/null
} > "$TMP/status.txt"

# Upload the slide the player says it's showing — works even when
# screencapture is TCC-blocked and only captures wallpaper.
DEST="${SIGNAGE_DEST:-$HOME/Signage}"
if [ -n "$NOW" ] && [ -f "$DEST/$NOW" ]; then
  "$RCLONE" copyto "$DEST/$NOW" "$REMOTE/_status/current-slide.${NOW##*.}" --timeout 60s 2>/dev/null
fi

[ -n "$SHOT" ] && "$RCLONE" copyto "$TMP/latest.png" "$REMOTE/_status/latest.png" --timeout 60s 2>/dev/null
[ -n "$SHOT" ] && [ -s "$TMP/latest2.png" ] && "$RCLONE" copyto "$TMP/latest2.png" "$REMOTE/_status/latest2.png" --timeout 60s 2>/dev/null
"$RCLONE" copyto "$TMP/status.txt" "$REMOTE/_status/status.txt" --timeout 60s 2>/dev/null
