# stopwatch-menubar

A minimal macOS menu bar stopwatch.

- **Click** the menu bar item to start or pause
- **Double-click** to reset
- **Right-click** for a Quit menu
- Display shows hours and minutes only (e.g. `0:00`, `1:23`)

## Requirements

- macOS 13 or later
- Swift 5.9+ (Command Line Tools is enough — full Xcode is **not** required)

## Build

```sh
./scripts/build-app.sh
```

This produces `Stopwatch.app` in the project root.

## Run

```sh
open Stopwatch.app
```

To run during development without bundling:

```sh
swift run
```

(In dev mode you may briefly see a Dock icon; once built into the `.app` bundle it runs as a pure menu bar app via `LSUIElement`.)

## Quit

Right-click the menu bar item and choose **Quit Stopwatch**, or press `⌘Q` while the context menu is open.

## Linux (Ubuntu)

A Python 3 + GTK3 port lives in `linux/`. Tested on Ubuntu 24.04 with
GNOME on X11.

### 1. Install system dependencies

```sh
sudo apt install python3-gi gir1.2-gtk-3.0 gnome-shell-extension-appindicator
# Optional but recommended (modern indicator API):
sudo apt install gir1.2-ayatanaappindicator3-0.1
# Optional toggle-click sound:
sudo apt install libcanberra-gtk3-module
```

`gnome-shell-extension-appindicator` is what makes tray icons visible on
GNOME 40+. If you've never enabled it, log out / back in after install
and turn it on in **Extensions**.

### 2. Run

```sh
cd linux
./scripts/run.sh
```

A small rounded box with the elapsed time appears in the top-right tray.

### 3. Install launcher entry (optional)

```sh
cd linux
./scripts/install-launcher.sh
```

Drops a `.desktop` entry in `~/.local/share/applications/` and a 256×256
icon in `~/.local/share/icons/hicolor/256x256/apps/`. Search `tally` in
Activities and the icon should appear within a few seconds.

### 4. Launch at login (optional)

Either toggle **Launch at Login** from the right-click menu, or run:

```sh
cd linux
./scripts/install-autostart.sh
```

### Where data lives

- Preferences: `~/.config/stopwatch-menubar/prefs.json`
- History:     `~/.local/share/stopwatch-menubar/history.json`

The history file format matches the macOS version (per-day, per-hour
buckets), so the same file copies cleanly between machines.

### Parity vs. macOS

Preserved in full: stopwatch toggle / reset / undo-reset (persisted
across restarts), display formats, per-period targets and locked-for-day
goals with the 4 AM rollover, daily total + per-period checkmarks,
per-hour history with carry-forward, calendar history window with
monthly heatmap, idle pause + return-prompt (XScreenSaver on X11,
`org.gnome.Mutter.IdleMonitor` on Wayland), launch-at-login, pixelated
firework celebrations on target hits, synthesized macOS-style
celebration sounds.

Dropped or simplified on Linux: `Cmd+Shift+S` global hotkey, scroll-on-
icon to nudge the timer (Linux tray APIs don't deliver scroll events to
the icon), the custom `.icns` icon (the tray icon is rendered live with
Cairo). Firework anchoring under the tray icon only works with the
legacy `Gtk.StatusIcon` backend; under `AyatanaAppIndicator3` it falls
back to the top-right of the primary monitor.

See `ROADMAP.md` for in-flight features (couples mode, shared calendar,
Windows port, account sync, phone screen-time integration) and the
macOS→Linux parity backport list.
