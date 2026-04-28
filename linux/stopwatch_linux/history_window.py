from __future__ import annotations

import calendar
from datetime import datetime

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import Gtk  # noqa: E402

from .history import HistoryStore


class HistoryWindow:
    def __init__(self, store: HistoryStore):
        self.store = store
        self._displayed_month = datetime.now().replace(day=1, hour=12)
        self._window: Gtk.Window | None = None
        self._month_label: Gtk.Label | None = None
        self._summary_label: Gtk.Label | None = None
        self._grid: Gtk.Grid | None = None

    def show(self) -> None:
        if self._window is None:
            self._window = self._build()
        self._refresh()
        self._window.show_all()
        self._window.present()

    def _build(self) -> Gtk.Window:
        win = Gtk.Window(title="Tally History")
        win.set_default_size(420, 380)
        win.set_resizable(False)
        win.connect("delete-event", self._on_close)

        outer = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        outer.set_margin_top(16)
        outer.set_margin_bottom(16)
        outer.set_margin_start(16)
        outer.set_margin_end(16)
        win.add(outer)

        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        prev_btn = Gtk.Button(label="◀")
        prev_btn.connect("clicked", lambda *_: self._shift_month(-1))
        header.pack_start(prev_btn, False, False, 0)

        self._month_label = Gtk.Label()
        self._month_label.set_xalign(0.5)
        header.pack_start(self._month_label, True, True, 0)

        next_btn = Gtk.Button(label="▶")
        next_btn.connect("clicked", lambda *_: self._shift_month(1))
        header.pack_start(next_btn, False, False, 0)

        outer.pack_start(header, False, False, 0)

        weekday_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=4, homogeneous=True)
        for sym in ["S", "M", "T", "W", "T", "F", "S"]:
            lbl = Gtk.Label(label=sym)
            lbl.set_xalign(0.5)
            weekday_row.pack_start(lbl, True, True, 0)
        outer.pack_start(weekday_row, False, False, 0)

        self._grid = Gtk.Grid()
        self._grid.set_row_spacing(4)
        self._grid.set_column_spacing(4)
        self._grid.set_row_homogeneous(True)
        self._grid.set_column_homogeneous(True)
        outer.pack_start(self._grid, True, True, 0)

        self._summary_label = Gtk.Label()
        self._summary_label.set_xalign(0)
        outer.pack_start(self._summary_label, False, False, 0)

        return win

    def _shift_month(self, delta: int) -> None:
        m = self._displayed_month
        new_month_index = m.month + delta
        new_year = m.year + (new_month_index - 1) // 12
        new_month = (new_month_index - 1) % 12 + 1
        self._displayed_month = m.replace(year=new_year, month=new_month, day=1)
        self._refresh()

    def _refresh(self) -> None:
        if self._month_label:
            self._month_label.set_markup(
                f"<b>{self._displayed_month.strftime('%B %Y')}</b>"
            )
        self._populate_grid()
        self._populate_summary()

    def _populate_grid(self) -> None:
        if self._grid is None:
            return
        for child in self._grid.get_children():
            self._grid.remove(child)

        month = self._displayed_month
        cal = calendar.Calendar(firstweekday=6)  # Sunday-first to match macOS default
        weeks = cal.monthdayscalendar(month.year, month.month)
        entries = self.store.entries_for_month(month)
        max_seconds = max((s for s in entries.values()), default=1)

        for row, week in enumerate(weeks):
            for col, day in enumerate(week):
                if day == 0:
                    cell = Gtk.Label(label="")
                    self._grid.attach(cell, col, row, 1, 1)
                    continue
                date = month.replace(day=day)
                seconds = self.store.seconds_for_day(date)
                self._grid.attach(self._make_day_cell(day, seconds, max_seconds), col, row, 1, 1)

        self._grid.show_all()

    def _make_day_cell(self, day: int, seconds: int, max_seconds: int) -> Gtk.Widget:
        intensity = min(1.0, seconds / max_seconds) if (seconds > 0 and max_seconds > 0) else 0
        # Use markup for color so we don't need a CSS provider
        if seconds > 0:
            duration = f"{seconds // 3600}:{(seconds % 3600) // 60:02d}"
            alpha = 0.22 + intensity * 0.55
            bg = f"rgba(74, 144, 226, {alpha:.2f})"
        else:
            duration = "—"
            bg = "rgba(120, 120, 120, 0.08)"

        ev = Gtk.EventBox()
        provider = Gtk.CssProvider()
        provider.load_from_data(
            f"eventbox {{ background-color: {bg}; border-radius: 4px; }}".encode()
        )
        ev.get_style_context().add_provider(
            provider, Gtk.STYLE_PROVIDER_PRIORITY_APPLICATION
        )

        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        box.set_margin_top(4)
        box.set_margin_bottom(4)
        box.set_margin_start(4)
        box.set_margin_end(4)
        day_lbl = Gtk.Label()
        day_lbl.set_markup(f"<span size='small' weight='bold'>{day}</span>")
        day_lbl.set_xalign(0)
        box.pack_start(day_lbl, False, False, 0)
        dur_lbl = Gtk.Label()
        dur_lbl.set_markup(f"<span size='x-small'>{duration}</span>")
        dur_lbl.set_xalign(1)
        box.pack_start(dur_lbl, False, False, 0)
        ev.add(box)
        return ev

    def _populate_summary(self) -> None:
        entries = self.store.entries_for_month(self._displayed_month)
        total = sum(entries.values())
        h = total // 3600
        m = (total % 3600) // 60
        if self._summary_label:
            self._summary_label.set_markup(
                f"<span size='small'>Total this month: {h}h {m:02d}m</span>"
            )

    def _on_close(self, win, _event):
        win.hide()
        return True
