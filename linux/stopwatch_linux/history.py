"""Per-hour activity history, JSON-compatible with the macOS app's format."""
from __future__ import annotations

import json
import os
from dataclasses import dataclass
from datetime import datetime, timedelta
from typing import Optional

from .periods import Period
from .preferences import Preferences
from .storage import HISTORY_PATH, ensure_dirs


DAY_SHIFT_HOUR = 4  # day rolls over at 4 AM, matching the Swift app


@dataclass
class PeriodBreakdown:
    raw: int
    effective: int
    carry_in: int
    carry_out: int


def day_key(date: datetime) -> str:
    if date.hour < DAY_SHIFT_HOUR:
        date = date - timedelta(days=1)
    return date.strftime("%Y-%m-%d")


class HistoryStore:
    SAVE_EVERY = 1

    def __init__(self):
        self.entries: dict[str, list[int]] = {}
        self._dirty = 0
        self._load()

    def _load(self) -> None:
        try:
            with HISTORY_PATH.open("r", encoding="utf-8") as f:
                decoded = json.load(f)
        except FileNotFoundError:
            return
        except (json.JSONDecodeError, OSError):
            return
        if not isinstance(decoded, dict):
            return
        for k, v in decoded.items():
            if isinstance(v, list) and len(v) == 24 and all(isinstance(x, int) for x in v):
                self.entries[k] = list(v)

    def _save(self) -> None:
        ensure_dirs()
        tmp = HISTORY_PATH.with_suffix(HISTORY_PATH.suffix + ".tmp")
        with tmp.open("w", encoding="utf-8") as f:
            json.dump(self.entries, f, sort_keys=True)
        os.replace(tmp, HISTORY_PATH)

    def flush(self) -> None:
        if self._dirty > 0:
            self._save()
            self._dirty = 0

    def record_second(self, when: Optional[datetime] = None) -> None:
        when = when or datetime.now()
        key = day_key(when)
        hour = when.hour
        arr = self.entries.get(key)
        if arr is None or len(arr) != 24:
            arr = [0] * 24
        arr[hour] += 1
        self.entries[key] = arr
        self._dirty += 1
        if self._dirty >= self.SAVE_EVERY:
            self._save()
            self._dirty = 0

    def seconds_for_day(self, date: datetime) -> int:
        return sum(self.entries.get(day_key(date), []))

    def seconds_for_period(self, period: Period, date: datetime) -> int:
        arr = self.entries.get(day_key(date))
        if not arr or len(arr) != 24:
            return 0
        return sum(arr[h] for h in range(24) if period.contains_hour(h))

    def period_breakdown(self, date: datetime) -> dict[Period, PeriodBreakdown]:
        prefs = Preferences.shared()
        dkey = day_key(date)
        result: dict[Period, PeriodBreakdown] = {}
        carry = 0
        order = Period.ordered()
        for period in order:
            raw = self.seconds_for_period(period, date)
            target = prefs.effective_target_minutes(period, dkey) * 60
            available = raw + carry
            carry_out = available - target if (target > 0 and available > target) else 0
            result[period] = PeriodBreakdown(
                raw=raw,
                effective=available,
                carry_in=carry,
                carry_out=carry_out,
            )
            carry = 0 if period is Period.NIGHT else carry_out
        return result

    def entries_for_month(self, month: datetime) -> dict[datetime, int]:
        first = month.replace(day=1, hour=12, minute=0, second=0, microsecond=0)
        if first.month == 12:
            next_month = first.replace(year=first.year + 1, month=1)
        else:
            next_month = first.replace(month=first.month + 1)
        days_in_month = (next_month - first).days
        result: dict[datetime, int] = {}
        for d in range(1, days_in_month + 1):
            day = first.replace(day=d)
            total = self.seconds_for_day(day)
            if total > 0:
                result[day] = total
        return result
