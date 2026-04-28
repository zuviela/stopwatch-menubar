"""Detect user idle time on Linux.

Strategy:
- X11 sessions: use libXss (XScreenSaverQueryInfo) via ctypes for accurate idle ms.
- Wayland fallback: shell out to `gdbus` against org.gnome.Mutter.IdleMonitor.
- Both unavailable: report 0 (idle detection effectively disabled).
"""
from __future__ import annotations

import ctypes
import os
import subprocess
from ctypes import c_int, c_ulong, POINTER, Structure
from typing import Callable, Optional


class _XScreenSaverInfo(Structure):
    _fields_ = [
        ("window", c_ulong),
        ("state", c_int),
        ("kind", c_int),
        ("til_or_since", c_ulong),
        ("idle", c_ulong),
        ("event_mask", c_ulong),
    ]


class _X11IdleProbe:
    def __init__(self):
        self._ok = False
        self._dpy = None
        self._info = None
        try:
            self._libX11 = ctypes.CDLL("libX11.so.6")
            self._libXss = ctypes.CDLL("libXss.so.1")
        except OSError:
            return
        self._libX11.XOpenDisplay.argtypes = [ctypes.c_char_p]
        self._libX11.XOpenDisplay.restype = ctypes.c_void_p
        self._libX11.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
        self._libX11.XDefaultRootWindow.restype = c_ulong
        self._libXss.XScreenSaverAllocInfo.restype = POINTER(_XScreenSaverInfo)
        self._libXss.XScreenSaverQueryInfo.argtypes = [
            ctypes.c_void_p,
            c_ulong,
            POINTER(_XScreenSaverInfo),
        ]
        self._libXss.XScreenSaverQueryInfo.restype = c_int
        self._dpy = self._libX11.XOpenDisplay(None)
        if not self._dpy:
            return
        self._root = self._libX11.XDefaultRootWindow(self._dpy)
        self._info = self._libXss.XScreenSaverAllocInfo()
        if not self._info:
            return
        self._ok = True

    def idle_seconds(self) -> Optional[float]:
        if not self._ok:
            return None
        if self._libXss.XScreenSaverQueryInfo(self._dpy, self._root, self._info) == 0:
            return None
        return self._info.contents.idle / 1000.0


class _MutterIdleProbe:
    """Falls back to org.gnome.Mutter.IdleMonitor over D-Bus when libXss isn't usable."""

    def __init__(self):
        self._ok = self._probe_once() is not None

    def _probe_once(self) -> Optional[float]:
        try:
            out = subprocess.check_output(
                [
                    "gdbus",
                    "call",
                    "--session",
                    "--dest",
                    "org.gnome.Mutter.IdleMonitor",
                    "--object-path",
                    "/org/gnome/Mutter/IdleMonitor/Core",
                    "--method",
                    "org.gnome.Mutter.IdleMonitor.GetIdletime",
                ],
                stderr=subprocess.DEVNULL,
                timeout=2,
            )
        except (FileNotFoundError, subprocess.SubprocessError):
            return None
        try:
            payload = out.decode().strip().strip("()").rstrip("uL,")
            ms = int(payload.split()[-1].rstrip(","))
        except (ValueError, IndexError):
            return None
        return ms / 1000.0

    def idle_seconds(self) -> Optional[float]:
        if not self._ok:
            return None
        return self._probe_once()


class IdleMonitor:
    """Polls idle time and emits onIdle / onReturn callbacks.

    `schedule` adds a GLib timeout and returns its source id; `unschedule`
    removes it. We keep only one active timer at a time across mode switches.
    Set `threshold = 0` to disable.
    """

    def __init__(
        self,
        schedule: Callable[[int, Callable[[], bool]], int],
        unschedule: Callable[[int], None],
        threshold_seconds: int = 300,
    ):
        self.threshold = threshold_seconds
        self.on_idle: Optional[Callable[[], None]] = None
        self.on_return: Optional[Callable[[], None]] = None
        self._mode = "watch_idle"
        self._idle_poll_ms = 5000
        self._return_poll_ms = 2000
        self._schedule = schedule
        self._unschedule = unschedule
        self._source_id: Optional[int] = None
        self._stopped = False
        self._probes = self._select_probes()

    @staticmethod
    def _select_probes():
        probes = []
        if os.environ.get("XDG_SESSION_TYPE", "").lower() != "wayland":
            x = _X11IdleProbe()
            if x._ok:
                probes.append(x)
        m = _MutterIdleProbe()
        if m._ok:
            probes.append(m)
        return probes

    def current_idle_seconds(self) -> float:
        for probe in self._probes:
            value = probe.idle_seconds()
            if value is not None:
                return value
        return 0.0

    def start(self) -> None:
        self._switch("watch_idle")

    def stop(self) -> None:
        self._stopped = True
        if self._source_id is not None:
            self._unschedule(self._source_id)
            self._source_id = None

    def update_threshold(self, seconds: int) -> None:
        self.threshold = max(0, int(seconds))
        if self.threshold == 0 and self._mode == "watch_return":
            self._switch("watch_idle")

    def _switch(self, mode: str) -> None:
        if self._source_id is not None:
            self._unschedule(self._source_id)
            self._source_id = None
        self._mode = mode
        interval = self._idle_poll_ms if mode == "watch_idle" else self._return_poll_ms
        self._source_id = self._schedule(interval, self._tick)

    def _tick(self) -> bool:
        if self._stopped:
            self._source_id = None
            return False
        if self._mode == "watch_idle":
            return self._check_idle()
        return self._check_return()

    def _check_idle(self) -> bool:
        if self.threshold <= 0:
            return True  # keep polling; threshold may be raised later
        idle = self.current_idle_seconds()
        if idle < self.threshold:
            return True
        if self.on_idle:
            self.on_idle()
        self._switch("watch_return")
        return False  # current source replaced by _switch

    def _check_return(self) -> bool:
        idle = self.current_idle_seconds()
        if idle >= 3:
            return True
        if self.on_return:
            self.on_return()
        self._switch("watch_idle")
        return False
