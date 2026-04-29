"""Render the rounded-rectangle text icon used in the system tray.

GNOME's panel renders tray icons as monochrome pixmaps. We draw with Cairo,
saving to a transient PNG file in a dedicated icons dir so the indicator
API can pick it up by name (Gtk.StatusIcon also accepts pixbufs directly).

AppIndicator + the GNOME appindicator extension cache icons by name. If we
reused a filename, the displayed icon would freeze even though the file
content changed — the indicator sees an unchanged IconName over D-Bus and
skips the reload. We give every render a unique counter-based name and
sweep older files so the icons dir doesn't grow forever.
"""
from __future__ import annotations

import itertools
import os
from pathlib import Path

import cairo

from .storage import DATA_DIR, ensure_dirs

ICONS_DIR = DATA_DIR / "icons"
_NAME_COUNTER = itertools.count()
_KEEP_RECENT = 4  # keep the last few PNGs so an in-flight indicator load isn't broken


def _measure_text(ctx: cairo.Context, text: str) -> tuple[float, float]:
    extents = ctx.text_extents(text)
    return extents.width, extents.height


_TRON_CYAN = (0.30, 0.85, 1.0, 1.0)  # Tron-style light blue


def render_status_image(text: str, scale: int = 2) -> Path:
    """Render `text` as a borderless monospaced label, return the PNG path.

    Matches the visual weight of GNOME's panel clock — no border, minimal
    padding, just the digits. `scale` raises pixel density for hi-dpi panels.
    """
    ensure_dirs()
    surface_for_measure = cairo.ImageSurface(cairo.FORMAT_ARGB32, 1, 1)
    ctx = cairo.Context(surface_for_measure)
    ctx.select_font_face("Monospace", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    point_size = 11.0
    ctx.set_font_size(point_size * scale)
    text_w, text_h = _measure_text(ctx, text)

    horizontal_padding = 2 * scale
    vertical_padding = 1 * scale

    width = int(text_w + horizontal_padding * 2 + 2)
    height = int(text_h + vertical_padding * 2 + 4)

    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, width, height)
    ctx = cairo.Context(surface)
    ctx.select_font_face("Monospace", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_NORMAL)
    ctx.set_font_size(point_size * scale)
    ctx.set_source_rgba(0, 0, 0, 0)
    ctx.paint()

    extents = ctx.text_extents(text)
    text_x = (width - extents.width) / 2 - extents.x_bearing
    text_y = (height + extents.height) / 2 - extents.y_bearing - extents.height
    ctx.move_to(text_x, text_y)
    ctx.set_source_rgba(*_TRON_CYAN)
    ctx.show_text(text)

    ICONS_DIR.mkdir(parents=True, exist_ok=True)
    counter = next(_NAME_COUNTER)
    out_path = ICONS_DIR / f"sw-{os.getpid()}-{counter}.png"
    surface.write_to_png(str(out_path))
    _sweep_old_icons(out_path)
    return out_path


def _sweep_old_icons(current: Path) -> None:
    """Delete stale icon PNGs so the dir doesn't grow without bound.

    Keeps the most recent _KEEP_RECENT files (by mtime); skips the file we
    just wrote in case the indicator is still loading it.
    """
    try:
        entries = sorted(
            ICONS_DIR.glob("sw-*.png"),
            key=lambda p: p.stat().st_mtime,
            reverse=True,
        )
    except OSError:
        return
    for stale in entries[_KEEP_RECENT:]:
        if stale == current:
            continue
        try:
            stale.unlink()
        except OSError:
            pass


def render_app_icon(out_path: Path, size: int = 256) -> Path:
    """Render the launcher icon: a stopwatch with a rounded-square clock face.

    Used by `scripts/install-launcher.sh` to produce a desktop-environment
    icon at install time so we don't need to ship a binary asset.
    """
    surface = cairo.ImageSurface(cairo.FORMAT_ARGB32, size, size)
    ctx = cairo.Context(surface)

    # Transparent background
    ctx.set_operator(cairo.OPERATOR_SOURCE)
    ctx.set_source_rgba(0, 0, 0, 0)
    ctx.paint()
    ctx.set_operator(cairo.OPERATOR_OVER)

    # Top button
    button_w = size * 0.18
    button_h = size * 0.06
    button_x = (size - button_w) / 2
    button_y = size * 0.06
    _rounded_rect(ctx, button_x, button_y, button_w, button_h, button_h / 2)
    ctx.set_source_rgba(0.18, 0.18, 0.20, 1.0)
    ctx.fill()

    # Clock face (large rounded square so the result reads as a "stopwatch")
    inset = size * 0.12
    face_x = inset
    face_y = size * 0.18
    face_w = size - inset * 2
    face_h = size - face_y - size * 0.06
    radius = face_w * 0.18
    _rounded_rect(ctx, face_x, face_y, face_w, face_h, radius)
    ctx.set_source_rgba(1, 1, 1, 1)
    ctx.fill()

    # Border
    _rounded_rect(ctx, face_x, face_y, face_w, face_h, radius)
    ctx.set_source_rgba(0.18, 0.18, 0.20, 1.0)
    ctx.set_line_width(size * 0.025)
    ctx.stroke()

    # "0:00" text in the face
    ctx.select_font_face("Sans", cairo.FONT_SLANT_NORMAL, cairo.FONT_WEIGHT_BOLD)
    font_size = size * 0.30
    ctx.set_font_size(font_size)
    text = "0:00"
    extents = ctx.text_extents(text)
    text_x = face_x + (face_w - extents.width) / 2 - extents.x_bearing
    text_y = face_y + (face_h + extents.height) / 2 - extents.y_bearing - extents.height
    ctx.move_to(text_x, text_y)
    ctx.set_source_rgba(0.18, 0.18, 0.20, 1.0)
    ctx.show_text(text)

    out_path.parent.mkdir(parents=True, exist_ok=True)
    surface.write_to_png(str(out_path))
    return out_path


def _rounded_rect(ctx: cairo.Context, x: float, y: float, w: float, h: float, r: float) -> None:
    import math

    ctx.new_path()
    ctx.arc(x + r, y + r, r, math.pi, 1.5 * math.pi)
    ctx.arc(x + w - r, y + r, r, 1.5 * math.pi, 0)
    ctx.arc(x + w - r, y + h - r, r, 0, 0.5 * math.pi)
    ctx.arc(x + r, y + h - r, r, 0.5 * math.pi, math.pi)
    ctx.close_path()
