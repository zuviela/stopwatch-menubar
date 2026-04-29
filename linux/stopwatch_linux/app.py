from __future__ import annotations

from datetime import datetime
from typing import Optional

import gi

gi.require_version("Gtk", "3.0")
from gi.repository import GLib, Gtk  # noqa: E402

from . import autostart, sound
from .firework import FireworkController, FireworkStyle, _fallback_anchor
from .history import HistoryStore, day_key
from .history_window import HistoryWindow
from .icon_renderer import render_status_image
from .idle_monitor import IdleMonitor
from .periods import Period
from .preferences import DisplayFormat, Preferences
from .stopwatch import StopwatchTimer, format_duration_compact, format_elapsed
from .targets_window import TargetsWindow
from .tray import TrayIcon


IDLE_THRESHOLD_OPTIONS = [
    ("Disabled", 0),
    ("1 minute", 60),
    ("5 minutes", 300),
    ("10 minutes", 600),
    ("15 minutes", 900),
    ("30 minutes", 1800),
    ("1 hour", 3600),
]


class StopwatchApp:
    """Top-level controller, mirroring AppDelegate from the Swift source.

    Drops macOS-specific niceties that don't translate cleanly:
    - Fireworks animations (CoreAnimation/NSWindow)
    - Cmd+Shift+S global hotkey (no portable Linux equivalent without root or
      a desktop-environment-specific keybinding API)
    - Cmd+scroll on the status icon (no scroll events on tray icons)
    Everything else — toggle, reset, history, targets, idle-pause, autostart —
    is preserved.
    """

    def __init__(self):
        self.stopwatch = StopwatchTimer()
        self.history = HistoryStore()
        self.history_window = HistoryWindow(self.history)
        self.targets_window = TargetsWindow()
        self.tray = TrayIcon(
            on_left_click=self._on_left_click,
            on_double_click=self._on_double_click,
        )
        self.idle = IdleMonitor(
            schedule=lambda ms, fn: GLib.timeout_add(ms, fn),
            unschedule=GLib.source_remove,
            threshold_seconds=Preferences.shared().idle_threshold_seconds,
        )
        self.idle.on_idle = self._on_idle_detected
        self.idle.on_return = self._on_user_returned

        self.fireworks = FireworkController(anchor_provider=self._firework_anchor)

        self._idle_pause_timestamp: Optional[datetime] = None
        self._period_achieved: dict[Period, bool] = {}
        self._daily_achieved: bool = False
        self._achievement_day_key: str = ""

    # ---------- Lifecycle ----------

    def run(self) -> None:
        self._refresh_label()
        self.tray.set_menu(self._build_menu())
        GLib.timeout_add(1000, self._tick)
        self._seed_achievement_state()
        self.idle.start()
        # Mirror the macOS launch firework as a "hello" celebration.
        GLib.timeout_add(1500, self._launch_firework)
        Gtk.main()
        self.stopwatch.save_state()
        self.history.flush()
        self.idle.stop()

    def _quit(self) -> None:
        Gtk.main_quit()

    # ---------- Tick / display ----------

    def _tick(self) -> bool:
        if self.stopwatch.is_running:
            self.history.record_second()
            self._check_for_achievement()
            self.stopwatch.save_state()
        self._refresh_label()
        # Don't rebuild the tray menu here — calling set_menu while the user
        # has the menu open would close and re-open it on every tick under
        # AppIndicator. The menu is rebuilt on user actions (toggle, reset,
        # display/idle changes, etc.), which keeps it fresh enough.
        return True

    def _refresh_label(self) -> None:
        fmt = Preferences.shared().display_format
        time_str = format_elapsed(self.stopwatch.elapsed_seconds, fmt)
        if fmt is DisplayFormat.HM:
            title = f"● {time_str}" if self.stopwatch.is_running else time_str
        else:
            title = time_str
        path = render_status_image(title)
        self.tray.update_image(path)

    # ---------- Click handling ----------

    def _on_left_click(self) -> None:
        self._cancel_pending_idle_return()
        self.stopwatch.toggle()
        sound.play_toggle()
        self._refresh_label()
        self.tray.set_menu(self._build_menu())

    def _on_double_click(self) -> None:
        self._cancel_pending_idle_return()
        self.stopwatch.reset()
        self._refresh_label()
        self.tray.set_menu(self._build_menu())

    # ---------- Idle handling ----------

    def _cancel_pending_idle_return(self) -> None:
        self._idle_pause_timestamp = None

    def _on_idle_detected(self) -> None:
        if not self.stopwatch.is_running:
            return
        self._idle_pause_timestamp = datetime.now()
        self.stopwatch.toggle()
        self._refresh_label()

    def _on_user_returned(self) -> None:
        pause_time = self._idle_pause_timestamp
        if pause_time is None:
            return
        extra_away = int((datetime.now() - pause_time).total_seconds())
        self._idle_pause_timestamp = None
        if extra_away <= 0:
            return
        self._show_return_prompt(pause_time, extra_away)

    def _show_return_prompt(self, pause_time: datetime, extra_away: int) -> None:
        dialog = Gtk.MessageDialog(
            modal=True,
            message_type=Gtk.MessageType.QUESTION,
            buttons=Gtk.ButtonsType.NONE,
            text="Welcome back",
        )
        dialog.format_secondary_text(
            f"You stepped away for an extra {_format_away(extra_away)} after the timer paused. "
            "Add that to your tracked time?"
        )
        dialog.add_buttons(
            "Discard", Gtk.ResponseType.NO,
            "Keep", Gtk.ResponseType.YES,
        )
        dialog.set_default_response(Gtk.ResponseType.YES)
        response = dialog.run()
        dialog.destroy()
        if response == Gtk.ResponseType.YES:
            from datetime import timedelta
            self.stopwatch.add_elapsed(extra_away)
            for i in range(extra_away):
                self.history.record_second(pause_time + timedelta(seconds=i))
            if not self.stopwatch.is_running:
                self.stopwatch.toggle()
                sound.play_toggle()
        self._refresh_label()
        self.tray.set_menu(self._build_menu())

    # ---------- Achievements ----------

    def _seed_achievement_state(self) -> None:
        today = datetime.now()
        dkey = day_key(today)
        self._achievement_day_key = dkey
        breakdown = self.history.period_breakdown(today)
        prefs = Preferences.shared()
        for period in Period.ordered():
            target = prefs.effective_target_minutes(period, dkey) * 60
            effective = breakdown[period].effective if period in breakdown else 0
            self._period_achieved[period] = target > 0 and effective >= target
        daily_target = prefs.effective_daily_target_minutes(dkey) * 60
        daily_elapsed = self.history.seconds_for_day(today)
        self._daily_achieved = daily_target > 0 and daily_elapsed >= daily_target

    def _check_for_achievement(self) -> None:
        today = datetime.now()
        dkey = day_key(today)
        if dkey != self._achievement_day_key:
            self._achievement_day_key = dkey
            self._period_achieved = {}
            self._daily_achieved = False

        prefs = Preferences.shared()
        breakdown = self.history.period_breakdown(today)
        for period in Period.ordered():
            target = prefs.effective_target_minutes(period, dkey) * 60
            if target <= 0 or self._period_achieved.get(period):
                continue
            if breakdown[period].effective >= target:
                self._period_achieved[period] = True
                self.fireworks.play(FireworkStyle.SMALL)

        daily_target = prefs.effective_daily_target_minutes(dkey) * 60
        if daily_target > 0 and not self._daily_achieved:
            if self.history.seconds_for_day(today) >= daily_target:
                self._daily_achieved = True
                self.fireworks.play(FireworkStyle.GRAND)

    def _firework_anchor(self) -> tuple[int, int]:
        anchor = self.tray.get_anchor_below()
        if anchor is not None:
            return anchor
        return _fallback_anchor()

    def _launch_firework(self) -> bool:
        self.fireworks.play(FireworkStyle.GRAND)
        return False  # one-shot

    # ---------- Menu construction ----------

    def _build_menu(self) -> Gtk.Menu:
        menu = Gtk.Menu()

        toggle_item = Gtk.MenuItem(
            label=("Pause" if self.stopwatch.is_running else "Start")
        )
        toggle_item.connect("activate", lambda *_: self._on_left_click())
        menu.append(toggle_item)

        reset_item = Gtk.MenuItem(label="Reset")
        reset_item.connect("activate", lambda *_: self._on_double_click())
        menu.append(reset_item)

        undo_item = Gtk.MenuItem(label="Undo Reset")
        undo_item.set_sensitive(self.stopwatch.can_undo_reset)
        undo_item.connect("activate", lambda *_: self._on_undo_reset())
        menu.append(undo_item)

        menu.append(Gtk.SeparatorMenuItem())

        menu.append(self._build_display_submenu())
        menu.append(self._build_targets_submenu())
        menu.append(self._build_idle_submenu())

        menu.append(Gtk.SeparatorMenuItem())

        history_item = Gtk.MenuItem(label="Show History…")
        history_item.connect("activate", lambda *_: self.history_window.show())
        menu.append(history_item)

        targets_item = Gtk.MenuItem(label="Set Targets…")
        targets_item.connect("activate", lambda *_: self.targets_window.show())
        menu.append(targets_item)

        menu.append(self._build_test_fireworks_submenu())

        menu.append(Gtk.SeparatorMenuItem())

        autostart_item = Gtk.CheckMenuItem(label="Launch at Login")
        autostart_item.set_active(autostart.is_enabled())
        autostart_item.connect("toggled", self._on_autostart_toggled)
        menu.append(autostart_item)

        menu.append(Gtk.SeparatorMenuItem())

        quit_item = Gtk.MenuItem(label="Quit Tally")
        quit_item.connect("activate", lambda *_: self._quit())
        menu.append(quit_item)

        menu.show_all()
        return menu

    def _build_display_submenu(self) -> Gtk.MenuItem:
        item = Gtk.MenuItem(label="Display")
        submenu = Gtk.Menu()
        current = Preferences.shared().display_format
        # Build all radios + set initial state BEFORE connecting handlers.
        # set_active in a radio group fires activate on the radio being
        # deactivated; if the handler is already connected it would treat
        # that as a user action and overwrite the pref.
        group = []
        radios: list[tuple[Gtk.RadioMenuItem, DisplayFormat]] = []
        for fmt in DisplayFormat:
            radio = Gtk.RadioMenuItem.new_with_label(group, fmt.label)
            group = radio.get_group()
            radios.append((radio, fmt))
            submenu.append(radio)
        for radio, fmt in radios:
            radio.set_active(fmt is current)
        for radio, fmt in radios:
            radio.connect("activate", self._on_set_display_format, fmt)
        item.set_submenu(submenu)
        return item

    def _build_idle_submenu(self) -> Gtk.MenuItem:
        item = Gtk.MenuItem(label="Idle Pause After")
        submenu = Gtk.Menu()
        current = Preferences.shared().idle_threshold_seconds
        group = []
        radios: list[tuple[Gtk.RadioMenuItem, int]] = []
        for label, seconds in IDLE_THRESHOLD_OPTIONS:
            radio = Gtk.RadioMenuItem.new_with_label(group, label)
            group = radio.get_group()
            radios.append((radio, seconds))
            submenu.append(radio)
        for radio, seconds in radios:
            radio.set_active(seconds == current)
        for radio, seconds in radios:
            radio.connect("activate", self._on_set_idle_threshold, seconds)
        item.set_submenu(submenu)
        return item

    def _build_test_fireworks_submenu(self) -> Gtk.MenuItem:
        item = Gtk.MenuItem(label="Test Fireworks")
        submenu = Gtk.Menu()
        small = Gtk.MenuItem(label="Period (small)")
        small.connect("activate", lambda *_: self.fireworks.play(FireworkStyle.SMALL))
        submenu.append(small)
        grand = Gtk.MenuItem(label="Daily Goal (big)")
        grand.connect("activate", lambda *_: self.fireworks.play(FireworkStyle.GRAND))
        submenu.append(grand)
        item.set_submenu(submenu)
        return item

    def _build_targets_submenu(self) -> Gtk.MenuItem:
        item = Gtk.MenuItem(label="Targets")
        submenu = Gtk.Menu()
        today = datetime.now()
        dkey = day_key(today)
        prefs = Preferences.shared()
        is_locked = prefs.goals_are_locked(dkey)

        daily_min = prefs.effective_daily_target_minutes(dkey)
        daily_elapsed = self.history.seconds_for_day(today)
        lock_suffix = "  (locked)" if is_locked else ""
        if daily_min == 0:
            daily_title = (
                f"Daily Total:  {format_duration_compact(daily_elapsed)}  /  not set{lock_suffix}"
            )
        else:
            daily_sec = daily_min * 60
            mark = "✓" if daily_elapsed >= daily_sec else "✗"
            daily_title = (
                f"Daily Total:  {format_duration_compact(daily_elapsed)}  /  "
                f"{format_duration_compact(daily_sec)}  {mark}{lock_suffix}"
            )
        daily_label = Gtk.MenuItem(label=daily_title)
        daily_label.set_sensitive(False)
        submenu.append(daily_label)
        submenu.append(Gtk.SeparatorMenuItem())

        breakdown = self.history.period_breakdown(today)
        for period in Period.ordered():
            b = breakdown[period]
            target_min = prefs.effective_target_minutes(period, dkey)
            target_sec = target_min * 60
            left_arrow = "← " if b.carry_in > 0 else ""
            right_arrow = " →" if b.carry_out > 0 else ""
            time_str = f"{left_arrow}{format_duration_compact(b.raw)}{right_arrow}"
            if target_min == 0:
                title = f"{period.label}:  {time_str}  /  not set"
            else:
                mark = "✓" if b.effective >= target_sec else "✗"
                title = (
                    f"{period.label}:  {time_str}  /  {format_duration_compact(target_sec)}  {mark}"
                )
            row = Gtk.MenuItem(label=title)
            row.set_sensitive(False)
            submenu.append(row)

        submenu.append(Gtk.SeparatorMenuItem())
        set_label = "Set Targets… (locked until 4 AM)" if is_locked else "Set Targets…"
        set_item = Gtk.MenuItem(label=set_label)
        set_item.connect("activate", lambda *_: self.targets_window.show())
        submenu.append(set_item)
        item.set_submenu(submenu)
        return item

    # ---------- Menu actions ----------

    def _on_undo_reset(self) -> None:
        self.stopwatch.undo_reset()
        self._refresh_label()
        self.tray.set_menu(self._build_menu())

    def _on_set_display_format(self, item, fmt: DisplayFormat) -> None:
        if Preferences.shared().display_format is fmt:
            return
        Preferences.shared().display_format = fmt
        self._refresh_label()
        self.tray.set_menu(self._build_menu())

    def _on_set_idle_threshold(self, item, seconds: int) -> None:
        if Preferences.shared().idle_threshold_seconds == seconds:
            return
        Preferences.shared().idle_threshold_seconds = seconds
        self.idle.update_threshold(seconds)
        if seconds == 0:
            self._cancel_pending_idle_return()
        self.tray.set_menu(self._build_menu())

    def _on_autostart_toggled(self, item) -> None:
        if item.get_active():
            autostart.enable()
        else:
            autostart.disable()


def _format_away(seconds: int) -> str:
    h = seconds // 3600
    m = (seconds % 3600) // 60
    s = seconds % 60
    if h > 0:
        return f"{h}h {m}m"
    if m > 0:
        return f"{m}m {s}s" if s > 0 else f"{m} min"
    return f"{s}s"
