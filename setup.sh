#!/bin/bash
# Bootstrap a FRESH Mac (macOS 12+) into a signage player. Assumes nothing.
# Run: ./setup.sh    (re-run it after any step that asks you to)
set -u

step()  { printf '\n\033[1m== %s\033[0m\n' "$*"; }
fail()  { printf '\033[31m%s\033[0m\n' "$*"; exit 1; }

step "1/5 Command Line Tools (git, python3)"
if ! xcode-select -p >/dev/null 2>&1; then
  xcode-select --install || true
  echo "A dialog should be installing Command Line Tools. When it finishes, run ./setup.sh again."
  echo "If the dialog fails ('software not available from the update server' — common on"
  echo "older macOS): download 'Command Line Tools for Xcode 14.2' manually from"
  echo "  https://developer.apple.com/download/all/  (free Apple ID login),"
  echo "install the dmg, then re-run ./setup.sh. python3 comes from this package —"
  echo "the player cannot run without it."
  exit 1
fi
echo "ok"

step "2/5 python3 + tkinter"
/usr/bin/python3 -c 'import tkinter' 2>/dev/null \
  || fail "python3/tkinter missing — finish the Command Line Tools install, then re-run."
echo "ok (Tk $(/usr/bin/python3 -c 'import tkinter;print(tkinter.TkVersion)'))"
echo "   (optional: install Python 3 from python.org for Tk 8.6 = full-color rendering)"

step "3/5 rclone"
if ! command -v rclone >/dev/null 2>&1 && [ ! -x /usr/local/bin/rclone ]; then
  echo "Installing rclone (needs your password for sudo)..."
  curl -fsSL https://rclone.org/install.sh | sudo bash || fail "rclone install failed — check network and re-run."
fi
echo "ok ($(rclone version 2>/dev/null | head -1 || /usr/local/bin/rclone version | head -1))"

step "4/5 Google Drive remote ('gdrive')"
RCLONE="$(command -v rclone || echo /usr/local/bin/rclone)"
if ! "$RCLONE" listremotes 2>/dev/null | grep -q '^gdrive:'; then
  echo "Opening a browser to authorize Google Drive."
  echo "Sign in with the signage account (dedicated account recommended)."
  "$RCLONE" config create gdrive drive || fail "rclone auth failed — re-run ./setup.sh"
fi
"$RCLONE" lsf "gdrive:Foyer Signage" >/dev/null 2>&1 \
  || echo "NOTE: 'Foyer Signage' folder not visible yet — create/share it in Drive; sync will pick it up."
echo "ok"

step "5/5 Install player + sync services"
DIR="$(cd "$(dirname "$0")" && pwd)"
"$DIR/install.sh" "$HOME/Signage"

cat <<'EOF'

Done. Remaining one-time manual settings (System Settings):
  1. sudo pmset -a disablesleep 1          (clamshell without keyboard)
  2. Lock Screen -> display off: Never; screen saver: off
  3. Energy Saver -> Start up after power failure
  4. Users & Groups -> auto-login this user (requires FileVault OFF)
  5. BetterDisplay/Displays -> rotate TV 270; TV as primary display
Content appears within ~1 min of dropping files in the Drive folder.
EOF
