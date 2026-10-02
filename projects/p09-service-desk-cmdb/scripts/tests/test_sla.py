"""Unit tests for P9 business-hour SLA logic (scripts/03-configure_glpi_sla.py).

Run from the project folder:
    python3 -m unittest discover -s scripts/tests -v
No network and no GLPI are needed: the deadline maths is pure.
"""

from __future__ import annotations

import datetime as dt
import importlib.util
import json
import pathlib
import sys
import unittest

HERE = pathlib.Path(__file__).resolve().parent
SCRIPT = HERE.parent / "03-configure_glpi_sla.py"
CONFIG = HERE.parent.parent / "configs" / "glpi-sla-priorities.json"

spec = importlib.util.spec_from_file_location("p09_sla", SCRIPT)
sla = importlib.util.module_from_spec(spec)
assert spec.loader is not None
sys.modules[spec.name] = sla  # dataclasses resolve their module through sys.modules
spec.loader.exec_module(sla)

# 2026-10-02 is a Friday (per the project clock), so 2026-10-05 is a Monday.
MON = dt.datetime(2026, 10, 5, 8, 0)
CAL = sla.Calendar(days={0, 1, 2, 3, 4}, start_minute=8 * 60, end_minute=18 * 60)


class AddBusinessMinutesTests(unittest.TestCase):
    def test_simple_add_within_the_day(self) -> None:
        self.assertEqual(sla.add_business_minutes(MON, 15, CAL), dt.datetime(2026, 10, 5, 8, 15))

    def test_exactly_to_closing(self) -> None:
        self.assertEqual(sla.add_business_minutes(MON, 600, CAL), dt.datetime(2026, 10, 5, 18, 0))

    def test_rolls_over_the_weekend(self) -> None:
        start = dt.datetime(2026, 10, 9, 17, 50)  # Friday
        self.assertEqual(sla.add_business_minutes(start, 15, CAL), dt.datetime(2026, 10, 12, 8, 5))

    def test_skips_a_holiday(self) -> None:
        calendar = sla.Calendar(days={0, 1, 2, 3, 4}, start_minute=8 * 60, end_minute=18 * 60,
                                holidays={dt.date(2026, 10, 12)})
        start = dt.datetime(2026, 10, 9, 17, 50)
        self.assertEqual(sla.add_business_minutes(start, 15, calendar), dt.datetime(2026, 10, 13, 8, 5))

    def test_multi_day_target(self) -> None:
        self.assertEqual(sla.add_business_minutes(MON, 2400, CAL), dt.datetime(2026, 10, 8, 18, 0))

    def test_start_before_opening(self) -> None:
        self.assertEqual(sla.add_business_minutes(dt.datetime(2026, 10, 5, 7, 0), 60, CAL),
                         dt.datetime(2026, 10, 5, 9, 0))

    def test_start_on_a_weekend(self) -> None:
        self.assertEqual(sla.add_business_minutes(dt.datetime(2026, 10, 10, 10, 0), 15, CAL),
                         dt.datetime(2026, 10, 12, 8, 15))

    def test_negative_minutes_rejected(self) -> None:
        with self.assertRaises(ValueError):
            sla.add_business_minutes(MON, -1, CAL)


class ParseCalendarTests(unittest.TestCase):
    def test_parses_the_real_config(self) -> None:
        with open(CONFIG, encoding="utf-8") as handle:
            raw = json.load(handle)["calendar"]
        calendar = sla.parse_calendar(raw)
        self.assertEqual(calendar.start_minute, 8 * 60)
        self.assertEqual(calendar.end_minute, 18 * 60)
        self.assertIn(0, calendar.days)
        self.assertNotIn(5, calendar.days)

    def test_rejects_end_before_start(self) -> None:
        with self.assertRaises(ValueError):
            sla.parse_calendar({"days": ["Mon"], "start": "18:00", "end": "08:00"})

    def test_clock_requires_minutes(self) -> None:
        with self.assertRaises(ValueError):
            sla._clock_to_minute("0800")


class DeadlineAndPayloadTests(unittest.TestCase):
    def setUp(self) -> None:
        with open(CONFIG, encoding="utf-8") as handle:
            self.config = json.load(handle)
        self.calendar = sla.parse_calendar(self.config["calendar"])

    def test_p1_deadlines(self) -> None:
        deadlines = sla.compute_deadlines("P1", MON, self.config["priorities"], self.calendar)
        self.assertEqual(deadlines["tto_due"], dt.datetime(2026, 10, 5, 8, 15))
        self.assertEqual(deadlines["ttr_due"], dt.datetime(2026, 10, 5, 12, 0))

    def test_unknown_priority_rejected(self) -> None:
        with self.assertRaises(KeyError):
            sla.compute_deadlines("P9", MON, self.config["priorities"], self.calendar)

    def test_payload_counts_match_the_config(self) -> None:
        payloads = sla.build_payloads(self.config)
        self.assertEqual(len(payloads["slas"]), len(self.config["priorities"]))
        self.assertEqual(len(payloads["business_rules"]), len(self.config["business_rules"]))
        self.assertEqual(len(payloads["groups"]), len(self.config["groups"]))


if __name__ == "__main__":
    unittest.main()
