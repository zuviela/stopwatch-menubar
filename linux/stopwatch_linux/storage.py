"""Filesystem locations and JSON-backed key/value preferences.

Mirrors the macOS app's storage layout but routed through XDG paths:
- preferences  -> $XDG_CONFIG_HOME/stopwatch-menubar/prefs.json
- history      -> $XDG_DATA_HOME/stopwatch-menubar/history.json
"""
from __future__ import annotations

import json
import os
from pathlib import Path
from typing import Any


def _xdg(env_var: str, fallback: Path) -> Path:
    raw = os.environ.get(env_var)
    return Path(raw) if raw else fallback


CONFIG_DIR: Path = _xdg("XDG_CONFIG_HOME", Path.home() / ".config") / "stopwatch-menubar"
DATA_DIR: Path = _xdg("XDG_DATA_HOME", Path.home() / ".local" / "share") / "stopwatch-menubar"

PREFS_PATH: Path = CONFIG_DIR / "prefs.json"
HISTORY_PATH: Path = DATA_DIR / "history.json"


def ensure_dirs() -> None:
    CONFIG_DIR.mkdir(parents=True, exist_ok=True)
    DATA_DIR.mkdir(parents=True, exist_ok=True)


class JSONStore:
    """Tiny JSON-backed key/value store, used as the UserDefaults equivalent.

    Multiple JSONStore instances may target the same file (StopwatchTimer
    and Preferences both back onto prefs.json). To stop one instance from
    clobbering another's keys on flush, every read goes through disk and
    every write is read-modify-write — the in-memory dict is just a cache
    that gets re-synced before any operation.
    """

    def __init__(self, path: Path):
        self.path = path
        self._data: dict[str, Any] = {}
        self._reload()

    def _reload(self) -> None:
        try:
            with self.path.open("r", encoding="utf-8") as f:
                loaded = json.load(f)
            if isinstance(loaded, dict):
                self._data = loaded
                return
        except FileNotFoundError:
            pass
        except (json.JSONDecodeError, OSError):
            pass
        self._data = {}

    def get(self, key: str, default: Any = None) -> Any:
        self._reload()
        return self._data.get(key, default)

    def set(self, key: str, value: Any) -> None:
        self._reload()
        self._data[key] = value
        self._flush()

    def remove(self, key: str) -> None:
        self._reload()
        if key in self._data:
            del self._data[key]
            self._flush()

    def has(self, key: str) -> bool:
        self._reload()
        return key in self._data

    def _flush(self) -> None:
        ensure_dirs()
        tmp = self.path.with_suffix(self.path.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as f:
            json.dump(self._data, f, indent=2, sort_keys=True)
        os.replace(tmp, self.path)
