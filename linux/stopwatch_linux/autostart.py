"""Manage 'Launch at Login' via XDG autostart .desktop file.

Equivalent to macOS SMAppService.mainApp on Linux: writing a .desktop file
to ~/.config/autostart/ tells the session manager to start the app on login.
"""
from __future__ import annotations

import os
import sys
from pathlib import Path


AUTOSTART_DIR = Path(os.environ.get("XDG_CONFIG_HOME", str(Path.home() / ".config"))) / "autostart"
AUTOSTART_FILE = AUTOSTART_DIR / "stopwatch-menubar.desktop"


def _exec_command() -> str:
    """Build the command that the autostart entry will run.

    Resolves to `python3 -m stopwatch_linux` from the project root, so the
    entry stays valid even if the project moves — we record the absolute
    project path in the desktop entry's working directory.
    """
    python = sys.executable or "python3"
    project_root = Path(__file__).resolve().parent.parent  # .../linux
    return f'{python} -m stopwatch_linux'


def _project_root() -> Path:
    return Path(__file__).resolve().parent.parent  # .../linux


def is_enabled() -> bool:
    return AUTOSTART_FILE.exists()


def enable() -> None:
    AUTOSTART_DIR.mkdir(parents=True, exist_ok=True)
    contents = (
        "[Desktop Entry]\n"
        "Type=Application\n"
        "Name=Tally\n"
        f"Exec={_exec_command()}\n"
        f"Path={_project_root()}\n"
        "X-GNOME-Autostart-enabled=true\n"
        "NoDisplay=false\n"
        "Terminal=false\n"
    )
    AUTOSTART_FILE.write_text(contents, encoding="utf-8")


def disable() -> None:
    try:
        AUTOSTART_FILE.unlink()
    except FileNotFoundError:
        pass
