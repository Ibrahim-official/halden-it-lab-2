"""Unit tests for scripts/analyze_fleet.py."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS_DIR))
sys.path.insert(0, str(SCRIPTS_DIR.parent / "data"))

import analyze_fleet  # noqa: E402


def row(department: str, **overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
        "Department": department,
        "OS": "Windows 11",
        "CPUGeneration": 13,
        "RAM_GB": 16,
        "Disk_GB": 512,
        "TPMVersion": 2.0,
        "SecureBoot": "Yes",
        "UEFI": "Yes",
    }
    base.update(overrides)
    return base


class AggregateTests(unittest.TestCase):
    def test_counts_by_status(self) -> None:
        rows = [
            row("Finance"),
            row("Finance", OS="Windows 10"),
            row("Warehouse", CPUGeneration=7),
        ]
        summary = analyze_fleet.aggregate(rows)
        self.assertEqual(summary["total"], 3)
        self.assertEqual(summary["status_counts"]["ready"], 1)
        self.assertEqual(summary["status_counts"]["upgrade"], 1)
        self.assertEqual(summary["status_counts"]["replace"], 1)

    def test_counts_group_by_department(self) -> None:
        rows = [row("Finance"), row("Finance", CPUGeneration=7), row("Sales")]
        summary = analyze_fleet.aggregate(rows)
        self.assertEqual(summary["by_department"]["Finance"]["ready"], 1)
        self.assertEqual(summary["by_department"]["Finance"]["replace"], 1)
        self.assertEqual(sum(analyze_fleet.aggregate(rows)["by_department"]["Sales"].values()), 1)

    def test_failure_reasons_are_collected(self) -> None:
        summary = analyze_fleet.aggregate([row("IT", TPMVersion=1.2, CPUGeneration=7)])
        self.assertTrue(any("TPM" in reason for reason in summary["reason_counts"]))

    def test_empty_fleet_is_safe(self) -> None:
        summary = analyze_fleet.aggregate([])
        self.assertEqual(summary["total"], 0)
        self.assertEqual(summary["status_counts"]["ready"], 0)

    def test_markdown_reports_total(self) -> None:
        summary = analyze_fleet.aggregate([row("Finance")])
        report = analyze_fleet.render_markdown(summary, "data/synthetic-fleet.csv")
        self.assertIn("Devices analysed: **1**", report)
        self.assertIn("synthetic", report.lower())


if __name__ == "__main__":
    unittest.main()
