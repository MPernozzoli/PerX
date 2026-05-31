"""Italian working-days calendar.

Port of `PerX/Services/AI/ItalianCalendarService.swift` +
`WorkScheduleManager.workingDaysUntilEndOfMonth`.

Pure-function module: no DB, no I/O. Easter is computed via
Meeus/Jones/Butcher.
"""
from __future__ import annotations

import math
from datetime import date, datetime, timedelta
from functools import lru_cache


_FIXED_HOLIDAYS: tuple[tuple[int, int], ...] = (
    (1, 1),    # Capodanno
    (1, 6),    # Epifania
    (4, 25),   # Liberazione
    (5, 1),    # Festa del Lavoro
    (6, 2),    # Repubblica
    (8, 15),   # Ferragosto
    (11, 1),   # Tutti i Santi
    (12, 8),   # Immacolata
    (12, 25),  # Natale
    (12, 26),  # Santo Stefano
)


def _easter(year: int) -> date:
    """Meeus/Jones/Butcher algorithm."""
    a = year % 19
    b = year // 100
    c = year % 100
    d = b // 4
    e = b % 4
    f = (b + 8) // 25
    g = (b - f + 1) // 3
    h = (19 * a + b - d - g + 15) % 30
    i = c // 4
    k = c % 4
    l = (32 + 2 * e + 2 * i - h - k) % 7
    m = (a + 11 * h + 22 * l) // 451
    month = (h + l - 7 * m + 114) // 31
    day = ((h + l - 7 * m + 114) % 31) + 1
    return date(year, month, day)


@lru_cache(maxsize=32)
def holidays_for_year(year: int) -> frozenset[date]:
    days: set[date] = {date(year, m, d) for m, d in _FIXED_HOLIDAYS}
    easter = _easter(year)
    days.add(easter)
    days.add(easter + timedelta(days=1))  # Pasquetta
    return frozenset(days)


def is_holiday(value: date | datetime) -> bool:
    d = value.date() if isinstance(value, datetime) else value
    return d in holidays_for_year(d.year)


def is_working_day(value: date | datetime) -> bool:
    d = value.date() if isinstance(value, datetime) else value
    # weekday(): Monday=0 .. Sunday=6
    if d.weekday() >= 5:
        return False
    return not is_holiday(d)


def working_days_until_end_of_month(today: date | datetime) -> int:
    """Numero di giorni lavorativi (inclusi) da `today` all'ultimo giorno del mese.

    `today` viene considerato come "oggi"; se è giorno lavorativo conta come 1.
    """
    d = today.date() if isinstance(today, datetime) else today
    if d.month == 12:
        end = date(d.year + 1, 1, 1) - timedelta(days=1)
    else:
        end = date(d.year, d.month + 1, 1) - timedelta(days=1)

    count = 0
    cursor = d
    while cursor <= end:
        if is_working_day(cursor):
            count += 1
        cursor += timedelta(days=1)
    return count
