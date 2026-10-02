#!/usr/bin/env python3
"""Unit tests for the P10 change-management logic.

Run from ``projects/p10-governance``:

    python3 scripts/tests/test_change_log.py
    python3 -m pytest scripts/tests/test_change_log.py   # if pytest is installed
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import change_log as cl  # noqa: E402
from _common import read_csv as read_csv_rows  # noqa: E402

FIELDS = [
    "change_id", "date_raised", "title", "change_type", "risk", "requested_by",
    "approver", "approval_date", "status", "category", "affected_services",
    "test_plan", "rollback_plan", "post_implementation_review", "cab_reference", "source",
]


def change_csv(path: Path, rows: list[dict[str, str]]) -> Path:
    import csv

    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        for row in rows:
            writer.writerow({f: row.get(f, "") for f in FIELDS})
    return path


def base_change(**overrides: str) -> dict[str, str]:
    row = {
        "change_id": "CHG-2026-100",
        "date_raised": "2026-10-01",
        "title": "A change",
        "change_type": "normal",
        "risk": "medium",
        "requested_by": "IT",
        "status": "pending",
        "category": "Infrastructure",
        "affected_services": "Logon",
        "test_plan": "Acceptance tests run",
        "rollback_plan": "Revert the snapshot and re-run the previous scripts",
        "cab_reference": "CAB-2026-10-05",
    }
    row.update(overrides)
    return row


class ChangeTypeTests(unittest.TestCase):
    def test_valid_types(self) -> None:
        self.assertEqual(cl.VALID_TYPES, {"standard", "normal", "emergency"})

    def test_valid_status_values(self) -> None:
        self.assertIn("pending", cl.VALID_STATUS)
        self.assertIn("reviewed", cl.VALID_STATUS)
        self.assertEqual(len(cl.VALID_STATUS), 7)

    def test_emergency_is_high_risk_example(self) -> None:
        self.assertIn("emergency", cl.VALID_TYPES)


class ValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def load(self, rows: list[dict[str, str]]) -> cl.Register:
        path = change_csv(self.root / "change-log.csv", rows)
        changes = [cl.Change(r) for r in read_csv_rows(path)]
        register = cl.Register(changes=changes, errors=[], warnings=[])
        cl.validate(register)
        return register

    def test_clean_change_has_no_errors(self) -> None:
        register = self.load([base_change()])
        self.assertEqual(register.errors, [])

    def test_missing_rollback_blocks_approval(self) -> None:
        register = self.load([base_change(rollback_plan="")])
        self.assertTrue(any("no rollback plan" in e for e in register.errors))

    def test_missing_required_field_is_flagged(self) -> None:
        register = self.load([base_change(test_plan="")])
        self.assertTrue(any("'test_plan' is empty" in e for e in register.errors))

    def test_bad_change_type_is_flagged(self) -> None:
        register = self.load([base_change(change_type="surprise")])
        self.assertTrue(any("change_type" in e for e in register.errors))

    def test_bad_status_is_flagged(self) -> None:
        register = self.load([base_change(status="maybe")])
        self.assertTrue(any("status" in e for e in register.errors))

    def test_approved_without_approver_is_flagged(self) -> None:
        register = self.load([base_change(status="approved", approver="")])
        self.assertTrue(any("no named approver" in e for e in register.errors))

    def test_reviewed_without_review_is_flagged(self) -> None:
        register = self.load(
            [base_change(status="reviewed", approver="IT Lead", approval_date="2026-10-02")]
        )
        self.assertTrue(any("post-implementation review is empty" in e for e in register.errors))

    def test_duplicate_id_is_flagged(self) -> None:
        register = self.load([base_change(), base_change()])
        self.assertTrue(any("duplicate change_id" in e for e in register.errors))

    def test_emergency_implemented_needs_retrospective(self) -> None:
        register = self.load(
            [
                base_change(
                    change_type="emergency",
                    status="implemented",
                    approver="IT Lead",
                    approval_date="2026-10-02",
                    post_implementation_review="",
                )
            ]
        )
        self.assertTrue(any("retrospective review" in e for e in register.errors))

    def test_emergency_with_retrospective_passes(self) -> None:
        register = self.load(
            [
                base_change(
                    change_type="emergency",
                    status="reviewed",
                    approver="IT Lead",
                    approval_date="2026-10-02",
                    post_implementation_review="Blocked the exploited port; retro held next day.",
                )
            ]
        )
        self.assertEqual(register.errors, [])

    def test_real_register_is_clean(self) -> None:
        register = cl.load_register()
        self.assertEqual(register.errors, [])


class KpiTests(unittest.TestCase):
    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def load(self, rows: list[dict[str, str]]) -> cl.Register:
        path = change_csv(self.root / "change-log.csv", rows)
        changes = [cl.Change(r) for r in read_csv_rows(path)]
        return cl.Register(changes=changes, errors=[], warnings=[])

    def test_counts_by_type(self) -> None:
        register = self.load(
            [
                base_change(change_id="C1", change_type="normal"),
                base_change(change_id="C2", change_type="standard", risk="low"),
                base_change(change_id="C3", change_type="emergency", risk="high"),
            ]
        )
        counts = register.kpi_counts(today=date(2026, 10, 10))
        self.assertEqual(counts["total_changes"], 3)
        self.assertEqual(counts["by_type"], {"normal": 1, "standard": 1, "emergency": 1})

    def test_emergency_share(self) -> None:
        register = self.load(
            [
                base_change(change_id="C1", change_type="normal"),
                base_change(change_id="C2", change_type="emergency", risk="high"),
            ]
        )
        counts = register.kpi_counts(today=date(2026, 10, 10))
        self.assertEqual(counts["emergency_share_percent"], 50.0)

    def test_unsigned_count(self) -> None:
        register = self.load([base_change(), base_change(change_id="C2", approver="IT Lead")])
        counts = register.kpi_counts(today=date(2026, 10, 10))
        self.assertEqual(counts["unsigned_approvals"], 1)

    def test_oldest_open_change_days(self) -> None:
        register = self.load([base_change(date_raised="2026-10-01")])
        counts = register.kpi_counts(today=date(2026, 10, 11))
        self.assertEqual(counts["oldest_open_change_days"], 10)

    def test_agenda_marks_decisions_pending(self) -> None:
        register = self.load([base_change()])
        agenda = cl.render_agenda(register, as_of=date(2026, 10, 5))
        self.assertIn("| CHG-2026-100 | pending |", agenda)
        self.assertIn("fictional", agenda)


if __name__ == "__main__":
    unittest.main(verbosity=2)
