from __future__ import annotations

from datetime import datetime

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

from .history import day_key
from .periods import Period
from .preferences import Preferences


class TargetsWindow:
    def __init__(self):
        self._window: Gtk.Window | None = None
        self._spinners: dict[Period, tuple[Gtk.SpinButton, Gtk.SpinButton]] = {}
        self._daily_label: Gtk.Label | None = None
        self._lock_button: Gtk.Button | None = None
        self._banner_label: Gtk.Label | None = None

    def show(self) -> None:
        if self._window is None:
            self._window = self._build()
        self._refresh_state()
        self._window.show_all()
        self._window.present()

    def _build(self) -> Gtk.Window:
        win = Gtk.Window(title="Tally Targets")
        win.set_default_size(460, 380)
        win.set_resizable(False)
        win.connect("delete-event", self._on_close)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        outer.set_margin_top(16)
        outer.set_margin_bottom(16)
        outer.set_margin_start(20)
        outer.set_margin_end(20)
        win.add(outer)

        title = Gtk.Label()
        title.set_markup("<b>Daily Targets</b>")
        title.set_halign(Gtk.Align.START)
        outer.pack_start(title, False, False, 0)

        explainer = Gtk.Label(
            label=(
                "Set 0 to disable a period. The daily total auto-sums the three "
                "periods — when met it fires a big firework; each period fires a "
                "smaller one. Periods are 5 AM–noon, noon–6 PM, and 6 PM–5 AM."
            )
        )
        explainer.set_line_wrap(True)
        explainer.set_xalign(0)
        outer.pack_start(explainer, False, False, 0)

        self._banner_label = Gtk.Label()
        self._banner_label.set_line_wrap(True)
        self._banner_label.set_xalign(0)
        outer.pack_start(self._banner_label, False, False, 0)

        daily_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        daily_row.pack_start(Gtk.Label(label="Daily Total (auto)"), False, False, 0)
        self._daily_label = Gtk.Label()
        self._daily_label.set_xalign(0)
        daily_row.pack_start(self._daily_label, True, True, 0)
        outer.pack_start(daily_row, False, False, 0)

        outer.pack_start(Gtk.Separator(), False, False, 0)

        for period in Period.ordered():
            outer.pack_start(self._build_row(period), False, False, 0)

        outer.pack_start(Gtk.Separator(), False, False, 0)

        bottom = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self._lock_button = Gtk.Button(label="Lock targets for today")
        self._lock_button.connect("clicked", self._on_lock_clicked)
        bottom.pack_end(self._lock_button, False, False, 0)
        outer.pack_start(bottom, False, False, 0)

        return win

    def _build_row(self, period: Period) -> Gtk.Box:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        label = Gtk.Label(label=period.label)
        label.set_xalign(0)
        label.set_size_request(96, -1)
        row.pack_start(label, False, False, 0)

        hours = Gtk.SpinButton.new_with_range(0, 23, 1)
        hours.connect("value-changed", lambda *_: self._on_value_changed(period))
        row.pack_start(hours, False, False, 0)
        row.pack_start(Gtk.Label(label="h"), False, False, 0)

        minutes = Gtk.SpinButton.new_with_range(0, 55, 5)
        minutes.connect("value-changed", lambda *_: self._on_value_changed(period))
        row.pack_start(minutes, False, False, 0)
        row.pack_start(Gtk.Label(label="m"), False, False, 0)

        self._spinners[period] = (hours, minutes)
        return row

    def _refresh_state(self) -> None:
        prefs = Preferences.shared()
        dkey = day_key(datetime.now())
        is_locked = prefs.goals_are_locked(dkey)
        locked_values = prefs.locked_goals(dkey) or {}

        for period, (h_spin, m_spin) in self._spinners.items():
            if is_locked and period in locked_values:
                total_min = locked_values[period]
            else:
                total_min = prefs.target_minutes(period)
            h_spin.set_value(total_min // 60)
            m_spin.set_value(total_min % 60)
            h_spin.set_sensitive(not is_locked)
            m_spin.set_sensitive(not is_locked)

        self._update_daily_label()

        if is_locked and self._banner_label:
            def fmt(minutes: int) -> str:
                h, m = minutes // 60, minutes % 60
                if h > 0 and m > 0:
                    return f"{h}h{m}m"
                if h > 0:
                    return f"{h}h"
                return f"{m}m"
            parts = [
                f"{period.label} {fmt(locked_values.get(period, 0))}"
                for period in Period.ordered()
            ]
            self._banner_label.set_markup(
                "<span size='small'>Locked until 4 AM: "
                + " · ".join(parts)
                + ". They'll unlock automatically for the next day.</span>"
            )
            self._banner_label.show()
        elif self._banner_label:
            self._banner_label.set_text("")

        if self._lock_button:
            self._lock_button.set_sensitive(not is_locked)
            self._lock_button.set_label(
                "Locked until 4 AM" if is_locked else "Lock targets for today"
            )

    def _on_value_changed(self, period: Period) -> None:
        prefs = Preferences.shared()
        dkey = day_key(datetime.now())
        if prefs.goals_are_locked(dkey):
            return
        h_spin, m_spin = self._spinners[period]
        prefs.set_target_minutes(int(h_spin.get_value()) * 60 + int(m_spin.get_value()), period)
        self._update_daily_label()

    def _update_daily_label(self) -> None:
        total_min = sum(
            int(h.get_value()) * 60 + int(m.get_value())
            for (h, m) in self._spinners.values()
        )
        h = total_min // 60
        m = total_min % 60
        text = f"{h}h {m:02d}m" if h > 0 else f"{m}m"
        if self._daily_label:
            self._daily_label.set_text(text)

    def _on_lock_clicked(self, _button) -> None:
        prefs = Preferences.shared()
        dkey = day_key(datetime.now())
        goals = {
            period: int(h.get_value()) * 60 + int(m.get_value())
            for period, (h, m) in self._spinners.items()
        }
        prefs.lock_goals(goals, dkey)
        self._refresh_state()

    def _on_close(self, win, _event):
        win.hide()
        return True
