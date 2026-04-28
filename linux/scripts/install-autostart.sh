#!/usr/bin/env bash
# Install the XDG autostart .desktop entry so the app runs at login.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
from stopwatch_linux import autostart
autostart.enable()
print(f"Installed: {autostart.AUTOSTART_FILE}")
PY
