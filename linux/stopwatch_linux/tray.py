"""Tray-icon abstraction.

Tries AyatanaAppIndicator3 first (correct API for GNOME with the
appindicator extension); falls back to legacy Gtk.StatusIcon if its GIR
bindings are missing. Both code paths surface the same `update_image`
and `set_menu` methods to the rest of the app.
"""
from __future__ import annotations

from pathlib import Path
from typing import Optional

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk, GdkPixbuf  # noqa: E402

try:
    gi.require_version("AyatanaAppIndicator3", "0.1")
    from gi.repository import AyatanaAppIndicator3 as _AppIndicator  # type: ignore

    _HAS_INDICATOR = True
except (ValueError, ImportError):
    try:
        gi.require_version("AppIndicator3", "0.1")
        from gi.repository import AppIndicator3 as _AppIndicator  # type: ignore

        _HAS_INDICATOR = True
    except (ValueError, ImportError):
        _AppIndicator = None
        _HAS_INDICATOR = False


class TrayIcon:
    """Common surface for both backends.

    on_left_click / on_double_click / on_right_click are called by the
    StatusIcon backend. The AppIndicator backend cannot distinguish click
    types, so it treats every interaction as opening the menu — but it also
    exposes a "secondary" activate signal for middle-clicks which we map to
    "toggle".
    """

    def __init__(
        self,
        on_left_click=None,
        on_double_click=None,
        on_right_click=None,
        on_toggle_shortcut=None,
    ):
        self.on_left_click = on_left_click
        self.on_double_click = on_double_click
        self.on_right_click = on_right_click
        self.on_toggle_shortcut = on_toggle_shortcut
        self._menu: Optional[Gtk.Menu] = None
        self._impl = self._make_impl()

    # ---------- Public API ----------

    def update_image(self, path: Path) -> None:
        if isinstance(self._impl, _IndicatorImpl):
            self._impl.set_icon_path(str(path))
        else:
            self._impl.set_pixbuf(path)

    def set_menu(self, menu: Gtk.Menu) -> None:
        self._menu = menu
        if isinstance(self._impl, _IndicatorImpl):
            self._impl.set_menu(menu)

    def get_anchor_below(self) -> Optional[tuple[int, int]]:
        """Return (screen_x, screen_y) directly below the tray icon, or None.

        Only the legacy StatusIcon backend exposes the icon geometry; the
        AppIndicator backend has no API for this on GNOME, so callers must
        handle None and fall back to a sensible position.
        """
        if isinstance(self._impl, _StatusIconImpl):
            return self._impl.icon_anchor_below()
        return None

    # ---------- Internal ----------

    def _make_impl(self):
        if _HAS_INDICATOR and _AppIndicator is not None:
            return _IndicatorImpl(self)
        return _StatusIconImpl(self)


class _IndicatorImpl:
    def __init__(self, tray: TrayIcon):
        self.tray = tray
        self.indicator = _AppIndicator.Indicator.new(
            "stopwatch-menubar",
            "",
            _AppIndicator.IndicatorCategory.APPLICATION_STATUS,
        )
        self.indicator.set_status(_AppIndicator.IndicatorStatus.ACTIVE)
        # Empty placeholder menu — replaced once the app builds its real one.
        placeholder = Gtk.Menu()
        placeholder.show_all()
        self.indicator.set_menu(placeholder)

    def set_menu(self, menu: Gtk.Menu) -> None:
        menu.show_all()
        self.indicator.set_menu(menu)

    def set_icon_path(self, path: str) -> None:
        self.indicator.set_icon_full(path, "Tally")


class _StatusIconImpl:
    def __init__(self, tray: TrayIcon):
        self.tray = tray
        self.icon = Gtk.StatusIcon()
        self.icon.set_visible(True)
        self.icon.connect("activate", self._on_activate)
        self.icon.connect("popup-menu", self._on_popup)
        self.icon.connect("button-press-event", self._on_button_press)
        self._last_click_was_double = False

    def set_pixbuf(self, path: Path) -> None:
        pb = GdkPixbuf.Pixbuf.new_from_file(str(path))
        self.icon.set_from_pixbuf(pb)

    def _on_button_press(self, _icon, event):
        # 2BUTTON_PRESS fires on the second click of a double; remember it
        # so the trailing single-click 'activate' becomes a no-op.
        from gi.repository import Gdk

        if event.type == Gdk.EventType._2BUTTON_PRESS and event.button == 1:
            self._last_click_was_double = True
            if self.tray.on_double_click:
                self.tray.on_double_click()
            return True
        return False

    def _on_activate(self, _icon):
        if self._last_click_was_double:
            self._last_click_was_double = False
            return
        if self.tray.on_left_click:
            self.tray.on_left_click()

    def _on_popup(self, icon, button, activate_time):
        menu = self.tray._menu
        if menu is None:
            return
        if self.tray.on_right_click:
            self.tray.on_right_click()
        menu.popup_at_pointer(None)

    def icon_anchor_below(self) -> Optional[tuple[int, int]]:
        """Return (x, y) directly below the StatusIcon's screen rect."""
        ok, _screen, area, _orientation = self.icon.get_geometry()
        if not ok:
            return None
        return (area.x + area.width // 2, area.y + area.height + 2)
