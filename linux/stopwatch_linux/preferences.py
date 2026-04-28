from __future__ import annotations

from enum import Enum

from .periods import Period
from .storage import JSONStore, PREFS_PATH


class DisplayFormat(Enum):
    HM = "hm"
    HMS = "hms"

    @property
    def label(self) -> str:
        return {DisplayFormat.HM: "H:MM", DisplayFormat.HMS: "H:MM:SS"}[self]


class Preferences:
    """Mirrors the Swift Preferences singleton; uses JSONStore in place of UserDefaults."""

    _instance: "Preferences | None" = None

    DISPLAY_FORMAT_KEY = "displayFormat"
    LOCKED_GOALS_KEY = "lockedGoalsByDay"
    IDLE_THRESHOLD_KEY = "idleThresholdSeconds"
    MAX_LOCKED_DAYS = 60

    def __init__(self):
        self.store = JSONStore(PREFS_PATH)

    @classmethod
    def shared(cls) -> "Preferences":
        if cls._instance is None:
            cls._instance = cls()
        return cls._instance

    @property
    def display_format(self) -> DisplayFormat:
        raw = self.store.get(self.DISPLAY_FORMAT_KEY)
        try:
            return DisplayFormat(raw) if raw else DisplayFormat.HMS
        except ValueError:
            return DisplayFormat.HMS

    @display_format.setter
    def display_format(self, value: DisplayFormat) -> None:
        self.store.set(self.DISPLAY_FORMAT_KEY, value.value)

    def _target_key(self, period: Period) -> str:
        return f"target_{period.value}_minutes"

    def target_minutes(self, period: Period) -> int:
        return int(self.store.get(self._target_key(period), 0) or 0)

    def set_target_minutes(self, minutes: int, period: Period) -> None:
        self.store.set(self._target_key(period), max(0, int(minutes)))

    @property
    def daily_target_minutes(self) -> int:
        return sum(self.target_minutes(p) for p in Period.ordered())

    def _locked_goals_raw(self) -> dict:
        raw = self.store.get(self.LOCKED_GOALS_KEY) or {}
        return raw if isinstance(raw, dict) else {}

    def locked_goals(self, day_key: str) -> dict[Period, int] | None:
        day_dict = self._locked_goals_raw().get(day_key)
        if not isinstance(day_dict, dict):
            return None
        result: dict[Period, int] = {}
        for raw, minutes in day_dict.items():
            try:
                period = Period(raw)
            except ValueError:
                continue
            result[period] = max(0, int(minutes))
        return result

    def goals_are_locked(self, day_key: str) -> bool:
        return day_key in self._locked_goals_raw()

    def lock_goals(self, goals: dict[Period, int], day_key: str) -> None:
        all_locked = self._locked_goals_raw()
        all_locked[day_key] = {p.value: max(0, int(m)) for p, m in goals.items()}
        if len(all_locked) > self.MAX_LOCKED_DAYS:
            kept = sorted(all_locked.keys(), reverse=True)[: self.MAX_LOCKED_DAYS]
            all_locked = {k: all_locked[k] for k in kept}
        self.store.set(self.LOCKED_GOALS_KEY, all_locked)

    def effective_target_minutes(self, period: Period, day_key: str) -> int:
        locked = self.locked_goals(day_key)
        if locked and period in locked:
            return locked[period]
        return self.target_minutes(period)

    def effective_daily_target_minutes(self, day_key: str) -> int:
        return sum(self.effective_target_minutes(p, day_key) for p in Period.ordered())

    @property
    def idle_threshold_seconds(self) -> int:
        raw = self.store.get(self.IDLE_THRESHOLD_KEY)
        if raw is None:
            return 300
        try:
            return max(0, int(raw))
        except (TypeError, ValueError):
            return 300

    @idle_threshold_seconds.setter
    def idle_threshold_seconds(self, value: int) -> None:
        self.store.set(self.IDLE_THRESHOLD_KEY, max(0, int(value)))
