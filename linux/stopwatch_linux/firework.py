"""Pixelated firework animation for target-hit celebrations.

A faithful port of the macOS SwiftUI Canvas implementation:
- N bursts at staggered start times, each a ring of M particles expanding
  outward, with gravity pulling them down and alpha fading over the burst
  lifetime.
- Grand style additionally rains sparkles that fall from random offsets.
- Animation steps at 12fps to keep the chunky 8x8-pixel look.

Window strategy:
- Borderless, undecorated top-level (POPUP) with an RGBA visual so it can
  composite as transparent on the desktop.
- Frames are rendered into a cairo ImageSurface in pure Python and pushed
  to a Gtk.Image as a GdkPixbuf. We deliberately avoid the GTK draw signal
  so the optional `python3-gi-cairo` foreign-type bridge isn't required.
- Click-through via Gdk.Window.set_pass_through (GTK 3.18+) so the firework
  doesn't intercept clicks while it's on screen.
- Positioned beneath the tray icon when the legacy StatusIcon backend is in
  use (it exposes geometry); otherwise anchored under the top-right corner
  of the primary monitor as a best-effort fallback (AppIndicator doesn't
  expose icon geometry on GNOME).
"""
from __future__ import annotations

import io
import math
import random
import shutil
import subprocess
import time
from dataclasses import dataclass
from enum import Enum
from typing import Callable, Optional

import cairo
import gi

gi.require_version("Gtk", "3.0")
gi.require_version("Gdk", "3.0")
from gi.repository import Gdk, GdkPixbuf, GLib, Gtk  # noqa: E402

from . import audio_assets  # noqa: E402


# ---------- Style ----------

class FireworkStyle(Enum):
    SMALL = "small"
    GRAND = "grand"


@dataclass(frozen=True)
class _StyleParams:
    burst_count: int
    particle_min: int
    particle_max: int
    start_delay_step: float
    radius_min: float
    radius_max: float
    life_min: float
    life_max: float
    spread_x: float
    spread_y: float
    sparkle_count: int
    total_duration: float
    display_duration: float
    window_w: int
    window_h: int
    palettes: list[list[tuple[float, float, float]]]
    burst_sound_times: list[float]
    burst_sound_name: str  # see audio_assets.POP / BOTTLE


# Colors as RGB triples (0-1 floats), close to the SwiftUI named colors.
_PINK_RED = (1.0, 0.2, 0.7)
_AMBER = (1.0, 0.8, 0.4)
_RED = (1.0, 0.23, 0.19)
_YELLOW = (1.0, 0.85, 0.0)
_CYAN = (0.27, 0.82, 0.96)
_WHITE = (1.0, 1.0, 1.0)
_GREEN = (0.30, 0.85, 0.39)
_ORANGE = (1.0, 0.58, 0.0)
_PURPLE = (0.69, 0.32, 0.87)
_PINK = (1.0, 0.55, 0.78)
_BLUE = (0.0, 0.48, 1.0)


_SMALL = _StyleParams(
    burst_count=3,
    particle_min=8,
    particle_max=10,
    start_delay_step=0.22,
    radius_min=50.0,
    radius_max=75.0,
    life_min=1.0,
    life_max=1.2,
    spread_x=55.0,
    spread_y=20.0,
    sparkle_count=0,
    total_duration=1.4,
    display_duration=1.8,
    window_w=320,
    window_h=180,
    palettes=[
        [_RED, _YELLOW],
        [_CYAN, _WHITE],
        [_GREEN, _YELLOW],
        [_PINK_RED, _WHITE],
        [_ORANGE, _YELLOW],
        [_PURPLE, _PINK],
    ],
    burst_sound_times=[0.0, 0.22],
    burst_sound_name=audio_assets.POP,
)


_GRAND = _StyleParams(
    burst_count=4,
    particle_min=12,
    particle_max=16,
    start_delay_step=0.32,
    radius_min=65.0,
    radius_max=100.0,
    life_min=1.2,
    life_max=1.5,
    spread_x=90.0,
    spread_y=30.0,
    sparkle_count=70,
    total_duration=2.6,
    display_duration=3.2,
    window_w=440,
    window_h=260,
    palettes=[
        [_RED, _YELLOW, _WHITE],
        [_CYAN, _WHITE, _BLUE],
        [_GREEN, _YELLOW, _WHITE],
        [_PINK_RED, _WHITE, _YELLOW],
        [_ORANGE, _YELLOW, _RED],
        [_PURPLE, _PINK, _WHITE],
    ],
    burst_sound_times=[0.0, 0.32, 0.64, 0.96],
    burst_sound_name=audio_assets.BOTTLE,
)


def _params_for(style: FireworkStyle) -> _StyleParams:
    return _GRAND if style is FireworkStyle.GRAND else _SMALL


# ---------- Particle geometry ----------

@dataclass
class _Burst:
    center_dx: float
    center_dy: float
    colors: list[tuple[float, float, float]]
    particle_count: int
    start_delay: float
    max_radius: float
    angle_jitter: float
    life_span: float


@dataclass
class _Sparkle:
    origin_dx: float
    origin_dy: float
    color: tuple[float, float, float]
    start_delay: float
    fall_speed: float
    lifetime: float


_SPARKLE_COLORS = [_YELLOW, _WHITE, _ORANGE, _RED, _CYAN, _AMBER]


def _build_bursts(p: _StyleParams) -> list[_Burst]:
    out: list[_Burst] = []
    for i in range(p.burst_count):
        out.append(
            _Burst(
                center_dx=random.uniform(-p.spread_x, p.spread_x),
                center_dy=random.uniform(-10, p.spread_y),
                colors=random.choice(p.palettes),
                particle_count=random.randint(p.particle_min, p.particle_max),
                start_delay=i * p.start_delay_step,
                max_radius=random.uniform(p.radius_min, p.radius_max),
                angle_jitter=random.uniform(0, 2 * math.pi),
                life_span=random.uniform(p.life_min, p.life_max),
            )
        )
    return out


def _build_sparkles(p: _StyleParams) -> list[_Sparkle]:
    out: list[_Sparkle] = []
    for _ in range(p.sparkle_count):
        out.append(
            _Sparkle(
                origin_dx=random.uniform(-150, 150),
                origin_dy=random.uniform(-60, 40),
                color=random.choice(_SPARKLE_COLORS),
                start_delay=random.uniform(0.6, 2.0),
                fall_speed=random.uniform(35, 90),
                lifetime=random.uniform(0.7, 1.1),
            )
        )
    return out


# ---------- Window ----------

_PIXEL_SIZE = 8
_FRAME_RATE = 12  # 12 fps animation matches the SwiftUI version's stepped look
_FRAME_INTERVAL_MS = int(1000 / _FRAME_RATE)


class _FireworkWindow(Gtk.Window):
    def __init__(self, style: FireworkStyle, anchor_x: int, anchor_y: int):
        super().__init__(type=Gtk.WindowType.POPUP)
        self._style = style
        self._params = _params_for(style)
        self._bursts = _build_bursts(self._params)
        self._sparkles = _build_sparkles(self._params)
        self._start_time = time.monotonic()
        self._tick_source: Optional[int] = None
        self._auto_close_source: Optional[int] = None
        self._destroyed = False

        self.set_app_paintable(True)
        self.set_decorated(False)
        self.set_resizable(False)
        self.set_skip_pager_hint(True)
        self.set_skip_taskbar_hint(True)
        self.set_accept_focus(False)
        self.set_focus_on_map(False)
        self.set_keep_above(True)
        self.set_type_hint(Gdk.WindowTypeHint.NOTIFICATION)

        screen = self.get_screen()
        visual = screen.get_rgba_visual()
        if visual is not None and screen.is_composited():
            self.set_visual(visual)

        self.set_default_size(self._params.window_w, self._params.window_h)
        self.move(
            anchor_x - self._params.window_w // 2,
            max(0, anchor_y),
        )

        self._image = Gtk.Image()
        self.add(self._image)

        self.connect("realize", self._on_realize)
        self.connect("destroy", self._on_destroy)

    def play(self) -> None:
        self.show_all()
        self._render_frame()  # paint frame 0 immediately
        self._tick_source = GLib.timeout_add(_FRAME_INTERVAL_MS, self._on_frame)
        self._auto_close_source = GLib.timeout_add(
            int(self._params.display_duration * 1000), self._auto_close
        )

    def _on_realize(self, _widget) -> None:
        gdk_window = self.get_window()
        if gdk_window is not None:
            # set_pass_through makes pointer events fall through to the window
            # underneath. Available since GTK 3.18 (Ubuntu 24.04 has 3.24).
            try:
                gdk_window.set_pass_through(True)
            except (AttributeError, TypeError):
                pass

    def _on_destroy(self, _widget) -> None:
        self._destroyed = True
        if self._tick_source is not None:
            GLib.source_remove(self._tick_source)
            self._tick_source = None
        if self._auto_close_source is not None:
            GLib.source_remove(self._auto_close_source)
            self._auto_close_source = None

    def _on_frame(self) -> bool:
        if self._destroyed:
            return False
        self._render_frame()
        return True

    def _auto_close(self) -> bool:
        self._auto_close_source = None
        if not self._destroyed:
            self.destroy()
        return False

    # ---------- Drawing ----------

    def _render_frame(self) -> None:
        w = self._params.window_w
        h = self._params.window_h
        surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, w, h)
        ctx = cairo.Context(surface)

        # Transparent canvas
        ctx.set_operator(cairo.OPERATOR_SOURCE)
        ctx.set_source_rgba(0, 0, 0, 0)
        ctx.paint()
        ctx.set_operator(cairo.OPERATOR_OVER)

        elapsed = time.monotonic() - self._start_time
        cx = w / 2
        cy = h / 2

        for burst in self._bursts:
            local = elapsed - burst.start_delay
            if local < 0:
                continue
            raw = min(local / burst.life_span, 1.0)
            stepped = math.floor(raw * _FRAME_RATE) / _FRAME_RATE
            self._draw_burst(ctx, burst, cx, cy, stepped)

        for sparkle in self._sparkles:
            local = elapsed - sparkle.start_delay
            if local < 0 or local > sparkle.lifetime:
                continue
            self._draw_sparkle(ctx, sparkle, cx, cy, local, local / sparkle.lifetime)

        # cairo ImageSurface -> PNG bytes -> GdkPixbuf -> Gtk.Image
        # PNG round-trip avoids the cairo<->GObject foreign-type binding so
        # python3-gi-cairo isn't needed.
        buf = io.BytesIO()
        surface.write_to_png(buf)
        buf.seek(0)
        loader = GdkPixbuf.PixbufLoader.new_with_type("png")
        loader.write(buf.read())
        loader.close()
        pixbuf = loader.get_pixbuf()
        if pixbuf is not None and not self._destroyed:
            self._image.set_from_pixbuf(pixbuf)

    def _draw_burst(
        self,
        ctx: cairo.Context,
        burst: _Burst,
        base_x: float,
        base_y: float,
        progress: float,
    ) -> None:
        if progress < 0.6:
            alpha = 1.0
        elif progress < 0.85:
            alpha = 0.6
        elif progress < 1.0:
            alpha = 0.3
        else:
            return
        radius = burst.max_radius * math.sqrt(progress)
        gravity = progress * progress * 32
        center_x = base_x + burst.center_dx
        center_y = base_y + burst.center_dy
        for i in range(burst.particle_count):
            angle = (i / burst.particle_count) * 2 * math.pi + burst.angle_jitter
            x = center_x + math.cos(angle) * radius
            y = center_y + math.sin(angle) * radius + gravity
            color = burst.colors[i % len(burst.colors)]
            self._draw_pixel(ctx, x, y, color, alpha)

    def _draw_sparkle(
        self,
        ctx: cairo.Context,
        sparkle: _Sparkle,
        base_x: float,
        base_y: float,
        elapsed: float,
        life_progress: float,
    ) -> None:
        if life_progress < 0.35:
            alpha = 1.0
        elif life_progress < 0.7:
            alpha = 0.55
        elif life_progress < 1.0:
            alpha = 0.25
        else:
            return
        x = base_x + sparkle.origin_dx
        y = base_y + sparkle.origin_dy + sparkle.fall_speed * elapsed
        self._draw_pixel(ctx, x, y, sparkle.color, alpha)

    def _draw_pixel(
        self,
        ctx: cairo.Context,
        x: float,
        y: float,
        color: tuple[float, float, float],
        alpha: float,
    ) -> None:
        snapped_x = math.floor(x / _PIXEL_SIZE) * _PIXEL_SIZE
        snapped_y = math.floor(y / _PIXEL_SIZE) * _PIXEL_SIZE
        ctx.rectangle(snapped_x, snapped_y, _PIXEL_SIZE, _PIXEL_SIZE)
        ctx.set_source_rgba(color[0], color[1], color[2], alpha)
        ctx.fill()


# ---------- Sound ----------

def _have(tool: str) -> bool:
    return shutil.which(tool) is not None


def _play_sound_file(path: str) -> None:
    if _have("paplay"):
        cmd = ["paplay", path]
    elif _have("aplay"):
        cmd = ["aplay", "-q", path]
    else:
        return
    try:
        subprocess.Popen(cmd, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except (FileNotFoundError, OSError):
        pass


def _schedule_burst_sounds(times: list[float], sound_name: str) -> None:
    """Play the synthesized firework sound at each offset in `times`."""
    path = audio_assets.get_sound_path(sound_name)
    if path is None:
        return
    sound_path = str(path)
    for t in times:
        delay_ms = int(t * 1000)
        if delay_ms <= 0:
            _play_sound_file(sound_path)
        else:
            GLib.timeout_add(delay_ms, lambda p=sound_path: (_play_sound_file(p), False)[1])


# ---------- Public controller ----------

class FireworkController:
    """Plays at most one firework window at a time.

    `anchor_provider` returns a (screen_x, screen_y) tuple for the bottom of
    the tray icon (or a sensible fallback). The window is centered
    horizontally on that x and starts its top edge at that y.
    """

    def __init__(self, anchor_provider: Callable[[], tuple[int, int]]):
        self._anchor_provider = anchor_provider
        self._current: Optional[_FireworkWindow] = None

    def play(self, style: FireworkStyle) -> None:
        # Close any in-flight firework so a new one always wins.
        if self._current is not None:
            try:
                self._current.destroy()
            except Exception:
                pass
            self._current = None

        try:
            anchor_x, anchor_y = self._anchor_provider()
        except Exception:
            anchor_x, anchor_y = _fallback_anchor()

        win = _FireworkWindow(style, anchor_x, anchor_y)
        win.connect("destroy", self._on_window_destroyed)
        self._current = win
        win.play()
        params = _params_for(style)
        _schedule_burst_sounds(params.burst_sound_times, params.burst_sound_name)

    def _on_window_destroyed(self, win: Gtk.Window) -> None:
        if self._current is win:
            self._current = None


def _fallback_anchor() -> tuple[int, int]:
    """Top-right of the primary monitor, just below the panel."""
    display = Gdk.Display.get_default()
    if display is None:
        return (800, 60)
    monitor = display.get_primary_monitor() or display.get_monitor(0)
    if monitor is None:
        return (800, 60)
    geom = monitor.get_geometry()
    # Anchor a little to the left of the right edge, just under the top panel.
    return (geom.x + geom.width - 200, geom.y + 32)
