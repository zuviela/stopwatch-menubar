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
