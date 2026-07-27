#!/usr/bin/env python3
"""Foyer signage player — fullscreen image rotator.

Plays every image in a folder (Google Drive for Desktop mirror), sorted by
filename. Optional config.json in the folder root. No third-party deps:
tkinter for display, sips for decode/resize (handles jpg/png/gif/heic).

Crash philosophy: any unexpected error logs and exits; launchd relaunches us
clean (see install.sh). The app never tries to limp along in a weird state.

Usage: player.py [folder]   (or SIGNAGE_DIR env; else auto-detects Drive)
"""
import hashlib
import json
import os
import random
import re
import subprocess
import sys
import time
import tkinter as tk

HOME = os.path.expanduser("~")
LOG_PATH = os.path.join(HOME, "signage.log")
LOG_MAX_BYTES = 1_000_000
CACHE_DIR = os.path.join(HOME, ".signage-cache")
CACHE_MAX_AGE_S = 30 * 86400
EXTS = {".jpg", ".jpeg", ".png", ".gif", ".heic"}
HEARTBEAT_S = 300
OFFHOURS_POLL_MS = 60_000
EMPTY_POLL_MS = 30_000
FADE_S = 0.5
DEFAULTS = {"seconds_per_slide": 12, "shuffle": False, "transition": "cut", "hours": None}
FOLDER_NAME = "Foyer Signage"


def log(msg):
    try:
        if os.path.exists(LOG_PATH) and os.path.getsize(LOG_PATH) > LOG_MAX_BYTES:
            os.replace(LOG_PATH, LOG_PATH + ".1")
        with open(LOG_PATH, "a") as f:
            f.write(time.strftime("%Y-%m-%d %H:%M:%S ") + msg + "\n")
    except OSError:
        pass


def find_folder():
    if len(sys.argv) > 1:
        return os.path.expanduser(sys.argv[1])
    if os.environ.get("SIGNAGE_DIR"):
        return os.path.expanduser(os.environ["SIGNAGE_DIR"])
    cloud = os.path.join(HOME, "Library", "CloudStorage")
    if os.path.isdir(cloud):
        for acct in sorted(os.listdir(cloud)):
            if not acct.startswith("GoogleDrive-"):
                continue
            candidates = [os.path.join(cloud, acct, "My Drive", FOLDER_NAME)]
            shared = os.path.join(cloud, acct, "Shared drives")
            if os.path.isdir(shared):
                for drv in sorted(os.listdir(shared)):
                    candidates.append(os.path.join(shared, drv, FOLDER_NAME))
            for c in candidates:
                if os.path.isdir(c):
                    return c
    return os.path.join(HOME, "Signage")


def natural_key(name):
    return [int(t) if t.isdigit() else t.lower() for t in re.split(r"(\d+)", name)]


def parse_hhmm(s):
    h, m = s.split(":")
    return int(h) * 60 + int(m)


def within_hours(hours):
    if not hours:
        return True
    try:
        now = time.localtime()
        cur = now.tm_hour * 60 + now.tm_min
        on, off = parse_hhmm(hours["on"]), parse_hhmm(hours["off"])
        if on <= off:
            return on <= cur < off
        return cur >= on or cur < off  # window crosses midnight
    except (KeyError, ValueError, AttributeError):
        return True


def prune_cache():
    try:
        os.makedirs(CACHE_DIR, exist_ok=True)
        cutoff = time.time() - CACHE_MAX_AGE_S
        for f in os.listdir(CACHE_DIR):
            p = os.path.join(CACHE_DIR, f)
            if os.path.getmtime(p) < cutoff:
                os.remove(p)
    except OSError:
        pass


# Tk < 8.6 can't load PNG; fall back to GIF (256 colors, still fine for signage,
# but README recommends a Tk 8.6+ python for photo quality).
CACHE_FMT = "png" if tk.TkVersion >= 8.6 else "gif"


def prepared_image(path, max_dim):
    """Decode/resize any supported format to a cached file tkinter can load."""
    st = os.stat(path)
    key = hashlib.md5(f"{path}|{st.st_mtime}|{st.st_size}|{max_dim}".encode()).hexdigest()
    out = os.path.join(CACHE_DIR, f"{key}.{CACHE_FMT}")
    if not os.path.exists(out):
        os.makedirs(CACHE_DIR, exist_ok=True)
        r = subprocess.run(
            ["sips", "-s", "format", CACHE_FMT, "--resampleHeightWidthMax", str(max_dim),
             path, "--out", out],
            capture_output=True, timeout=60)
        if r.returncode != 0 or not os.path.exists(out):
            raise RuntimeError(f"sips failed: {r.stderr.decode(errors='replace')[:200]}")
    return out


class Player:
    def __init__(self, folder):
        self.folder = folder
        self.cfg = dict(DEFAULTS)
        self.order = []
        self.idx = 0
        self.photo = None  # keep a reference or tk garbage-collects the image
        self.last_beat = 0.0
        self.root = tk.Tk()
        self.root.attributes("-fullscreen", True)
        self.root.configure(bg="black", cursor="none")
        self.canvas = tk.Canvas(self.root, bg="black", highlightthickness=0)
        self.canvas.pack(fill="both", expand=True)
        self.root.bind("<Command-q>", lambda e: self.root.destroy())
        self.root.update_idletasks()
        self.w = self.root.winfo_screenwidth()
        self.h = self.root.winfo_screenheight()
        log(f"started: folder={folder} screen={self.w}x{self.h}")

    def run(self):
        self.tick()
        self.root.mainloop()

    def heartbeat(self):
        if time.time() - self.last_beat >= HEARTBEAT_S:
            self.last_beat = time.time()
            log(f"heartbeat idx={self.idx}/{len(self.order)}")

    def reload_config(self):
        path = os.path.join(self.folder, "config.json")
        if not os.path.exists(path):
            self.cfg = dict(DEFAULTS)
            return
        try:
            with open(path) as f:
                raw = json.load(f)
            cfg = dict(DEFAULTS)
            if isinstance(raw.get("seconds_per_slide"), (int, float)) and raw["seconds_per_slide"] > 0:
                cfg["seconds_per_slide"] = raw["seconds_per_slide"]
            if isinstance(raw.get("shuffle"), bool):
                cfg["shuffle"] = raw["shuffle"]
            if raw.get("transition") in ("cut", "fade"):
                cfg["transition"] = raw["transition"]
            if isinstance(raw.get("hours"), dict):
                cfg["hours"] = raw["hours"]
            self.cfg = cfg
        except (OSError, ValueError) as e:
            log(f"config.json unreadable, keeping last-good: {e}")

    def scan(self):
        try:
            names = [n for n in os.listdir(self.folder)
                     if os.path.splitext(n)[1].lower() in EXTS
                     and not n.startswith((".", "_"))]  # "_" = parked, never played
        except OSError as e:
            log(f"folder unreadable: {e}")
            names = []
        names.sort(key=natural_key)
        if names != [n for n in self.order if n in names] or not self.order:
            fresh = list(names)
            if self.cfg["shuffle"]:
                random.shuffle(fresh)
            self.order = fresh
            self.idx = self.idx % len(self.order) if self.order else 0
        return self.order

    def show_black(self):
        self.canvas.delete("all")

    def show_waiting(self):
        self.canvas.delete("all")
        self.canvas.create_text(
            self.w // 2, self.h // 2, fill="#666", font=("Helvetica", 28),
            justify="center",
            text=f"Waiting for content…\n\nDrop images into:\n{self.folder}")

    def show_image(self, name):
        img = prepared_image(os.path.join(self.folder, name), max(self.w, self.h))
        photo = tk.PhotoImage(file=img)
        if self.cfg["transition"] == "fade":
            self.fade_to(0.0)
        self.canvas.delete("all")
        self.canvas.create_image(self.w // 2, self.h // 2, image=photo)
        self.photo = photo
        if self.cfg["transition"] == "fade":
            self.fade_to(1.0)

    def fade_to(self, target):
        try:
            start = float(self.root.attributes("-alpha"))
        except tk.TclError:
            return
        steps = 12
        for i in range(1, steps + 1):
            self.root.attributes("-alpha", start + (target - start) * i / steps)
            self.root.update()
            time.sleep(FADE_S / 2 / steps)

    def tick(self):
        self.heartbeat()
        self.reload_config()
        if not within_hours(self.cfg["hours"]):
            self.show_black()
            self.root.after(OFFHOURS_POLL_MS, self.tick)
            return
        order = self.scan()
        if not order:
            self.show_waiting()
            self.root.after(EMPTY_POLL_MS, self.tick)
            return
        name = order[self.idx % len(order)]
        try:
            self.show_image(name)
        except (RuntimeError, tk.TclError, OSError, subprocess.TimeoutExpired) as e:
            log(f"skipping {name}: {e}")
            self.order.remove(name)
        self.idx = (self.idx + 1) % max(len(self.order), 1)
        self.root.after(int(self.cfg["seconds_per_slide"] * 1000), self.tick)


def main():
    folder = find_folder()
    prune_cache()
    # Belt-and-suspenders against display/system sleep; dies with us.
    caffeinate = subprocess.Popen(["caffeinate", "-disu"])
    try:
        Player(folder).run()
    finally:
        caffeinate.terminate()


if __name__ == "__main__":
    try:
        main()
    except Exception as e:  # log-and-die: launchd restarts us clean
        log(f"FATAL: {type(e).__name__}: {e}")
        raise
