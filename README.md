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

## One-time Mac setup

1. **Google Drive for Desktop**: sign in (use a dedicated account like
   `signage@`), set the folder to **Mirror** (not stream) so content survives
   network outages. The player auto-finds `Foyer Signage` in My Drive or a
   Shared drive; pass a path to `install.sh` to override.
2. **Never sleep**: `sudo pmset -a disablesleep 1` (required for clamshell
   with no keyboard). Also System Settings → Lock Screen → display off:
   Never; screen saver: off.
3. **Survive power failure**: System Settings → Energy Saver → "Start up
   automatically after a power failure". Enable **auto-login** for this user
   (FileVault must be off for auto-login to work).
4. **Display**: BetterDisplay (or Displays settings) → rotation 270° for the
   portrait TV. If the laptop ever runs lid-open, drag the menu bar onto the
   TV in Displays → Arrange so the TV is the primary display — the player
   fullscreens on the primary. In clamshell this is automatic. These settings
   persist across reboots.
5. **Python (optional but recommended)**: the stock `/usr/bin/python3` works
   but its Tk 8.5 forces 256-color GIF rendering. Installing Python 3 from
   python.org (bundles Tk 8.6+) gets full-quality PNG; `install.sh` picks the
   best python it finds automatically.
6. **Install the player**:

   ```sh
   ./install.sh                      # auto-detect Drive folder
   ./install.sh "/path/to/folder"    # or explicit
   ```

   Starts immediately, at every login, and relaunches within 10s if it dies.

## Operations

- Logs + 5-minute heartbeat: `~/signage.log` (rotates at 1 MB).
- Stop: `launchctl unload ~/Library/LaunchAgents/com.farm.signage.plist`
- Quit once (it will restart unless unloaded): Cmd-Q.
- Bad images are skipped and logged, never fatal. Empty folder shows a
  "waiting for content" card. Drive offline just keeps playing the last
  synced content.
- Image cache: `~/.signage-cache` (auto-pruned after 30 days).
