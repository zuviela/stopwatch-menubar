#!/usr/bin/env bash
# Install a .desktop launcher entry so the app shows up in GNOME's search /
# Activities overview. Run once per machine.
set -euo pipefail
cd "$(dirname "$0")/.."

python3 - <<'PY'
import os
import sys
from pathlib import Path

from stopwatch_linux.icon_renderer import render_app_icon

PROJECT_ROOT = Path(__file__).resolve().parent.parent if "__file__" in dir() else Path.cwd()
PROJECT_ROOT = Path.cwd()  # we cd'd into linux/ above

xdg_data = Path(os.environ.get("XDG_DATA_HOME", str(Path.home() / ".local" / "share")))
icon_path = xdg_data / "icons" / "hicolor" / "256x256" / "apps" / "stopwatch-menubar.png"
desktop_dir = xdg_data / "applications"
desktop_path = desktop_dir / "stopwatch-menubar.desktop"

render_app_icon(icon_path, size=256)
desktop_dir.mkdir(parents=True, exist_ok=True)

python_bin = sys.executable or "python3"
exec_cmd = f"{python_bin} -m stopwatch_linux"

desktop_path.write_text(
    f"""[Desktop Entry]
Type=Application
Name=Tally
GenericName=Menubar Stopwatch
Comment=Minimal tray-bar stopwatch with daily targets and history
Exec={exec_cmd}
Path={PROJECT_ROOT}
Icon=stopwatch-menubar
Terminal=false
Categories=Utility;
Keywords=stopwatch;timer;clock;tally;
StartupNotify=false
StartupWMClass=stopwatch-menubar
""",
    encoding="utf-8",
)

print(f"icon:   {icon_path}")
print(f"desktop: {desktop_path}")
print()
print("Search 'tally' in your Activities / app grid to launch.")
PY

# Refresh the desktop entry cache so search picks it up immediately.
if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
fi
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache -f -t "$HOME/.local/share/icons/hicolor" 2>/dev/null || true
fi
