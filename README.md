# Foyer Signage

Fullscreen image slideshow for the vertical lobby TV. An old Intel MacBook Pro
in clamshell mode plays images from a Google Drive folder. No dependencies
beyond stock macOS (python3 + tkinter + sips).

## For the team: updating the sign

1. Open the shared **Foyer Signage** folder in Google Drive.
2. Drop in images (`.jpg .png .gif .heic`). They play in **filename order** —
   prefix with numbers: `01-welcome.jpg`, `02-events.png`.
3. Delete or rename to reorder. Changes appear on the TV within ~1 minute.

That's it. No app, no login to anything but Drive.

## Optional config.json (in the folder root)

```json
{
  "seconds_per_slide": 12,
  "shuffle": false,
  "transition": "fade",
  "hours": {"on": "06:30", "off": "22:00"}
}
```

All keys optional; missing/broken config falls back to defaults (12s, no
shuffle, hard cut, 24/7). Outside `hours` the screen shows black.
`hours` may cross midnight (`"on": "18:00", "off": "02:00"`).

## One-time Mac setup (fresh machine, nothing pre-installed)

No git required — pull the tarball with stock curl:

```sh
cd ~ && curl -fsSL https://codeload.github.com/booherbg/2026-digital-signage/tar.gz/main | tar xz
mv 2026-digital-signage-main signage && cd signage
./setup.sh
```

**Self-updating**: a daily launchd agent (4:30 AM) runs `update.sh`, which
downloads the latest main-branch tarball, swaps files in place, and reloads
the services — push to GitHub and every sign updates itself within a day.
Run `./update.sh` manually to update immediately. Any failure (offline, bad
download) keeps the current version running; log: `~/signage-update.log`.

`setup.sh` assumes a bare Mac and walks every dependency:

1. Installs Xcode Command Line Tools if missing (git/python3/tkinter) — the
   OS shows a dialog; re-run `./setup.sh` when it finishes.
2. Verifies python3 + tkinter.
3. Installs **rclone** if missing (official installer, needs sudo). We use
   rclone instead of Google Drive for Desktop because Drive Desktop requires
   macOS 13+ and this machine runs 12.x. rclone's one-time browser auth
   stores a refresh token that survives reboots indefinitely.
4. Creates the `gdrive:` remote (one-time Google sign-in in a browser — use a
   dedicated account like `signage@`).
5. Runs `install.sh`, which installs TWO launchd agents:
   - `com.farm.signage` — the player (RunAtLoad + KeepAlive, restarts in 10s)
   - `com.farm.signage.sync` — `sync.sh` every 60s: `gdrive:Foyer Signage` →
     `~/Signage`. Never deletes local content when the remote is unreachable.

Then finish the manual settings `setup.sh` prints at the end:

- `sudo pmset -a disablesleep 1` (clamshell without a keyboard)
- Lock Screen → display off **Never**; screen saver off
- Energy Saver → **start up after power failure**; auto-login (FileVault off)
- BetterDisplay/Displays → TV rotation 270°; TV as **primary** display (drag
  the menu bar onto it in Arrange — only matters lid-open; clamshell is
  automatic). All persist across reboots.
- Optional: Python 3 from python.org (Tk 8.6+) for full-color PNG rendering
  instead of stock Tk 8.5's 256-color GIF; `install.sh` auto-picks the best
  python present.

Custom remote/folder: `SIGNAGE_REMOTE="gdrive:Some Folder" ./sync.sh` (edit
the plist to make it permanent), or `./install.sh "/path/to/folder"` to point
the player elsewhere.

## Operations

- Logs + 5-minute heartbeat: `~/signage.log`; sync log: `~/signage-sync.log`
  (both rotate at 1 MB).
- Stop: `launchctl unload ~/Library/LaunchAgents/com.farm.signage.plist`
- Quit once (it will restart unless unloaded): Cmd-Q.
- Bad images are skipped and logged, never fatal. Empty folder shows a
  "waiting for content" card. Drive offline just keeps playing the last
  synced content.
- Image cache: `~/.signage-cache` (auto-pruned after 30 days).
- **Proof of life**: every 10 min a screenshot of the TV output plus a status
  text lands in Drive at `Foyer Signage/_status/` — check it from anywhere.
  If `latest.png` only shows the desktop wallpaper, grant Screen Recording to
  bash/Terminal once: System Settings → Privacy & Security → Screen Recording
  (macOS prompts the first time `status.sh` runs).
- Filenames starting with `_` or `.` are never played — safe place to park
  drafts in the folder root (`_draft-holiday.jpg`).
