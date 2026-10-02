#!/usr/bin/env python3
"""P9 Phase 0/2: configure GLPI service levels, priorities and business rules.

What
    Reads the priority/SLA matrix and the service catalogue from ``configs/`` and
    turns them into GLPI objects: the business-hours calendar, the four SLA
    priorities with their time-to-own (TTO) and time-to-resolve (TTR) targets, and
    the auto-assignment business rules. By default it is a **dry run** that prints
    the computed deadlines; pass ``--apply`` to send the payloads to the GLPI REST
    API.

Where
    Run from a management host (or OPS01) on the isolated Halden lab network. The
    GLPI app token and user token are read from the environment
    (``GLPI_APP_TOKEN`` / ``GLPI_USER_TOKEN``) or the git-ignored ``.env`` — never
    from this file.

Why it is testable
    The deadline maths (business-hour arithmetic) is a set of pure functions so the
    unit tests in ``scripts/tests/test_sla.py`` can prove it without a live GLPI.

Safety
    Lab-only. No result is measured here: this script configures targets, it does
    not report SLA compliance.
"""

from __future__ import annotations

import argparse
import datetime as dt
import json
import logging
import os
import sys
import urllib.error
import urllib.request
from dataclasses import dataclass, field
from typing import Any, Iterable

LOGGER = logging.getLogger("p09.sla")

# Maps the calendar's day labels to Python's weekday numbers (Monday = 0).
DAY_INDEX = {"mon": 0, "tue": 1, "wed": 2, "thu": 3, "fri": 4, "sat": 5, "sun": 6}


@dataclass(frozen=True)
class Calendar:
    """A business-hours calendar used for all SLA deadline arithmetic."""

    days: set[int]
    start_minute: int
    end_minute: int
    holidays: set[dt.date] = field(default_factory=set)
    timezone: str = "UTC"

    def _at(self, day: dt.date, minute_of_day: int) -> dt.datetime:
        return dt.datetime.combine(day, dt.time(minute_of_day // 60, minute_of_day % 60))

    def is_business_day(self, day: dt.date) -> bool:
        return day.weekday() in self.days and day not in self.holidays

    def within_hours(self, moment: dt.datetime) -> bool:
        minute = moment.hour * 60 + moment.minute
        return self.is_business_day(moment.date()) and self.start_minute <= minute < self.end_minute

    def opening_on(self, day: dt.date) -> dt.datetime:
        return self._at(day, self.start_minute)

    def closing_on(self, day: dt.date) -> dt.datetime:
        return self._at(day, self.end_minute)

    def next_opening(self, moment: dt.datetime) -> dt.datetime:
        """Return the next time the desk is open at or after ``moment``."""
        if self.is_business_day(moment.date()):
            minute = moment.hour * 60 + moment.minute
            if minute < self.start_minute:
                return self.opening_on(moment.date())
        day = moment.date() + dt.timedelta(days=1)
        while not self.is_business_day(day):
            day += dt.timedelta(days=1)
        return self.opening_on(day)


def _clock_to_minute(value: str) -> int:
    hours, _, minutes = value.partition(":")
    if not minutes:
        raise ValueError(f"clock value must be HH:MM, got {value!r}")
    return int(hours) * 60 + int(minutes)


def parse_calendar(raw: dict[str, Any]) -> Calendar:
    """Turn the JSON calendar block into a :class:`Calendar` (pure)."""
    try:
        days = {DAY_INDEX[d.strip().lower()[:3]] for d in raw["days"]}
    except (KeyError, ValueError) as exc:  # pragma: no cover - defensive
        raise ValueError(f"invalid calendar days: {raw.get('days')!r}") from exc
    start = _clock_to_minute(raw["start"])
    end = _clock_to_minute(raw["end"])
    if end <= start:
        raise ValueError("calendar end must be after start")
    holidays = {dt.date.fromisoformat(h) for h in raw.get("holidays", [])}
    return Calendar(days=days, start_minute=start, end_minute=end, holidays=holidays,
                    timezone=raw.get("timezone", "UTC"))


def add_business_minutes(start: dt.datetime, minutes: int, calendar: Calendar) -> dt.datetime:
    """Add ``minutes`` of *business* time to ``start`` (pure, naive datetimes)."""
    if minutes < 0:
        raise ValueError("minutes must be >= 0")
    current = start
    remaining = minutes
    guard = 0
    while remaining > 0:
        guard += 1
        if guard > 10_000:  # pragma: no cover - unreachable with a sane calendar
            raise RuntimeError("business-minute loop did not converge")
        if not calendar.is_business_day(current.date()) or not calendar.within_hours(current):
            current = calendar.next_opening(current)
            continue
        available = int((calendar.closing_on(current.date()) - current).total_seconds() // 60)
        if available >= remaining:
            return current + dt.timedelta(minutes=remaining)
        remaining -= available
        current = calendar.next_opening(calendar.closing_on(current.date()))
    return current


def compute_deadlines(priority_code: str, opened_at: dt.datetime,
                      priorities: Iterable[dict[str, Any]], calendar: Calendar) -> dict[str, dt.datetime]:
    """Return the TTO and TTR deadlines for one ticket (pure)."""
    match = next((p for p in priorities if p["code"].upper() == priority_code.upper()), None)
    if match is None:
        raise KeyError(f"unknown priority code {priority_code!r}")
    return {
        "tto_due": add_business_minutes(opened_at, int(match["tto_business_minutes"]), calendar),
        "ttr_due": add_business_minutes(opened_at, int(match["ttr_business_minutes"]), calendar),
    }


def build_payloads(sla_cfg: dict[str, Any]) -> dict[str, list[dict[str, Any]]]:
    """Build the GLPI API object skeletons for SLAs, priorities and business rules."""
    calendar = sla_cfg["calendar"]
    sla_payloads = [
        {
            "name": f"SLA {p['code']} - {p['name']}",
            "comment": f"TTO {p['tto_business_minutes']} min / TTR {p['ttr_business_minutes']} min "
                       f"(business hours: {calendar['start']}-{calendar['end']} "
                       f"{','.join(calendar['days'])})",
            "type": "SLA",
            "tto_minutes": p["tto_business_minutes"],
            "ttr_minutes": p["ttr_business_minutes"],
            "calendar": calendar["name"],
        }
        for p in sla_cfg["priorities"]
    ]
    priority_payloads = [
        {
            "name": p["name"],
            "impact": p["impact"],
            "urgency": p["urgency"],
            "example": p["example"],
            "escalate_at_percent": p["escalate_at_percent"],
        }
        for p in sla_cfg["priorities"]
    ]
    rule_payloads = [dict(rule) for rule in sla_cfg["business_rules"]]
    group_payloads = [dict(group) for group in sla_cfg.get("groups", [])]
    return {
        "slas": sla_payloads,
        "priorities": priority_payloads,
        "business_rules": rule_payloads,
        "groups": group_payloads,
    }


class GlpiClient:
    """Minimal GLPI REST client. Tokens come from the environment, never the file."""

    def __init__(self, base_url: str, app_token: str, user_token: str) -> None:
        self.base_url = base_url.rstrip("/")
        self.app_token = app_token
        self.user_token = user_token
        self.session_token: str | None = None

    def _request(self, method: str, path: str, body: Any | None = None) -> Any:
        url = f"{self.base_url}/apirest.php/{path}"
        headers = {"App-Token": self.app_token, "Content-Type": "application/json"}
        if self.session_token:
            headers["Session-Token"] = self.session_token
        else:
            headers["Authorization"] = f"user_token {self.user_token}"
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310 (lab-internal URL)
            payload = response.read().decode()
        return json.loads(payload) if payload else {}

    def connect(self) -> None:
        self.session_token = self._request("GET", "initSession").get("session_token")

    def disconnect(self) -> None:
        if self.session_token:
            try:
                self._request("GET", "killSession")
            finally:
                self.session_token = None

    def upsert(self, item_type: str, payload: dict[str, Any]) -> None:
        self._request("POST", item_type, {"input": payload})


def _read_json(path: str) -> dict[str, Any]:
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Configure GLPI SLAs, priorities and business rules (dry run by default).")
    parser.add_argument("--sla-config", default=os.path.join(os.path.dirname(__file__), "..", "configs", "glpi-sla-priorities.json"))
    parser.add_argument("--glpi-url", default=os.environ.get("GLPI_URL", "https://glpi.halden.internal"))
    parser.add_argument("--apply", action="store_true", help="Send the payloads to GLPI (default is a dry run).")
    parser.add_argument("--sample-opened", default="2026-10-05T08:00:00", help="Sample ticket open time for the deadline preview (ISO 8601).")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    logging.basicConfig(level=args.log_level.upper(), format="%(asctime)s %(levelname)s %(message)s")
    sla_cfg = _read_json(args.sla_config)
    calendar = parse_calendar(sla_cfg["calendar"])
    payloads = build_payloads(sla_cfg)

    opened = dt.datetime.fromisoformat(args.sample_opened)
    LOGGER.info("Business calendar: %s %02d:%02d-%02d:%02d, holidays=%d",
                ",".join(sla_cfg["calendar"]["days"]), calendar.start_minute // 60,
                calendar.start_minute % 60, calendar.end_minute // 60, calendar.end_minute % 60,
                len(calendar.holidays))
    for priority in sla_cfg["priorities"]:
        deadlines = compute_deadlines(priority["code"], opened, sla_cfg["priorities"], calendar)
        LOGGER.info("%s %-8s TTO %s -> %s | TTR %s -> %s",
                    priority["code"], priority["name"], priority["tto_business_minutes"],
                    deadlines["tto_due"].isoformat(sep=" "), priority["ttr_business_minutes"],
                    deadlines["ttr_due"].isoformat(sep=" "))

    if not args.apply:
        LOGGER.info("Dry run complete. Payload summary: %s", {k: len(v) for k, v in payloads.items()})
        print(json.dumps(payloads, indent=2))
        return 0

    app_token = os.environ.get("GLPI_APP_TOKEN")
    user_token = os.environ.get("GLPI_USER_TOKEN")
    if not (app_token and user_token):
        LOGGER.error("GLPI_APP_TOKEN and GLPI_USER_TOKEN must be set to apply.")
        return 2
    client = GlpiClient(args.glpi_url, app_token, user_token)
    client.connect()
    try:
        for payload in payloads["slas"]:
            client.upsert("SLA", payload)
            LOGGER.info("Applied SLA: %s", payload["name"])
        for payload in payloads["business_rules"]:
            client.upsert("Rule", payload)
            LOGGER.info("Applied business rule: %s", payload["id"])
    finally:
        client.disconnect()
    LOGGER.info("GLPI SLA configuration applied.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
