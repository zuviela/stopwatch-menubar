from __future__ import annotations

import time
from typing import Optional

from .preferences import DisplayFormat
from .storage import JSONStore, PREFS_PATH


class StopwatchTimer:
    ELAPSED_KEY = "stopwatch.savedElapsedSeconds"
    LAST_CYCLE_KEY = "stopwatch.savedLastCycleSeconds"

    def __init__(self):
        self.store = JSONStore(PREFS_PATH)
        self._accumulated: float = 0.0
        self._running_since: Optional[float] = None
        self._last_cycle: Optional[int] = None
        self._load_state()

    @property
    def is_running(self) -> bool:
        return self._running_since is not None

    @property
    def can_undo_reset(self) -> bool:
        return self._last_cycle is not None

    @property
    def elapsed_seconds(self) -> int:
        live = (time.time() - self._running_since) if self._running_since is not None else 0.0
        return int(self._accumulated + live)

    def toggle(self) -> None:
        if self._running_since is not None:
            self._accumulated += time.time() - self._running_since
            self._running_since = None
        else:
            self._running_since = time.time()
        self.save_state()

    def reset(self) -> None:
        current = self.elapsed_seconds
        if current > 0:
            self._last_cycle = current
        self._accumulated = 0.0
        self._running_since = None
        self.save_state()

    def undo_reset(self) -> None:
        if self._last_cycle is None:
            return
        self._accumulated = float(self._last_cycle)
        self._running_since = None
        self._last_cycle = None
        self.save_state()

    def add_elapsed(self, seconds: int) -> None:
        self._accumulated += max(0, int(seconds))
        self.save_state()

    def subtract_elapsed(self, seconds: int) -> None:
        self._accumulated = max(0.0, self._accumulated - max(0, int(seconds)))
        self.save_state()

    def save_state(self) -> None:
        self.store.set(self.ELAPSED_KEY, self.elapsed_seconds)
        if self._last_cycle is not None:
            self.store.set(self.LAST_CYCLE_KEY, self._last_cycle)
        else:
            self.store.remove(self.LAST_CYCLE_KEY)

    def _load_state(self) -> None:
        saved = self.store.get(self.ELAPSED_KEY, 0)
        try:
            self._accumulated = float(max(0, int(saved)))
        except (TypeError, ValueError):
            self._accumulated = 0.0
        if self.store.has(self.LAST_CYCLE_KEY):
            try:
                self._last_cycle = int(self.store.get(self.LAST_CYCLE_KEY))
            except (TypeError, ValueError):
                self._last_cycle = None


def format_elapsed(seconds: int, fmt: DisplayFormat) -> str:
    h = seconds // 3600
    m = (seconds % 3600) // 60
    s = seconds % 60
    if fmt is DisplayFormat.HM:
        return f"{h:02d}:{m:02d}" if h > 0 else f"{m:02d}"
    return f"{h:02d}:{m:02d}:{s:02d}" if h > 0 else f"{m:02d}:{s:02d}"


def format_duration_compact(seconds: int) -> str:
    h = seconds // 3600
    m = (seconds % 3600) // 60
    if h > 0:
        return f"{h}h {m:02d}m"
    return f"{m}m"
