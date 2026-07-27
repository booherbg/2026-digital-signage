#!/bin/bash
# Self-update WITHOUT git: pull the main-branch tarball from GitHub, swap the
# files in place, re-install the launchd agents. Safe by design: any failure
# (offline, bad download, GitHub hiccup) leaves the current install running.
# Run manually, or let the daily launchd agent (install.sh) do it.
set -u

REPO="booherbg/2026-digital-signage"
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$HOME/signage-update.log"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

note() { echo "$(date '+%F %T') $*" | tee -a "$LOG"; }

curl -fsSL --max-time 120 \
  "https://codeload.github.com/${REPO}/tar.gz/refs/heads/main" \
  -o "$TMP/repo.tgz" || { note "update: download failed, keeping current version"; exit 0; }
tar -xzf "$TMP/repo.tgz" -C "$TMP" 2>/dev/null \
  || { note "update: bad archive, keeping current version"; exit 0; }

SRC="$(echo "$TMP"/*-main)"
# Sanity: refuse to install an archive that doesn't look like this project.
[ -f "$SRC/player.py" ] && [ -f "$SRC/install.sh" ] \
  || { note "update: archive missing expected files, aborting"; exit 0; }

if diff -rq "$SRC" "$DIR" -x '.git' -x '*.log' >/dev/null 2>&1; then
  note "update: already current"
  exit 0
fi

cp "$SRC"/*.sh "$SRC/player.py" "$SRC/README.md" "$SRC/config.example.json" "$DIR/"
chmod +x "$DIR"/*.sh
"$DIR/install.sh" "$HOME/Signage" >>"$LOG" 2>&1
note "update: new version applied and services reloaded"
