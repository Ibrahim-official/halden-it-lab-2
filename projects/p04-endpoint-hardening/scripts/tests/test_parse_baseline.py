"""Unit tests for scripts/parse_baseline.py."""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS_DIR))

import parse_baseline  # noqa: E402

SAMPLE_CSV = """Control,Category,Status
BitLocker OS volume encrypted,BitLocker,Passed
BitLocker key escrowed to AD,BitLocker,Failed
ASR all approved rules blocking,Windows Defender,Passed
Firewall all profiles enabled,Firewall,Passed
LAPS password age under 31 days,LAPS,Skipped
Credential Guard running,Device Guard,NotApplicable
"""

ANNOTATED_CSV = """# P4 baseline export - sample, not a lab result
# Columns: Control, Category, Status

Control,Category,Status
BitLocker OS volume encrypted,BitLocker,PASS
BitLocker key escrowed to AD,BitLocker,fail
"""


class SummariseTests(unittest.TestCase):
    def setUp(self) -> None:
        self.rows = [
            {"_control": "a", "_category": "BitLocker", "_status": "Passed"},
            {"_control": "b", "_category": "BitLocker", "_status": "Failed"},
            {"_control": "c", "_category": "Firewall", "_status": "Skipped"},
            {"_control": "d", "_category": "Device Guard", "_status": "NotApplicable"},
        ]

    def test_counts_each_status(self) -> None:
        summary = parse_baseline.summarise(self.rows)
        self.assertEqual(summary["counts"]["passed"], 1)
        self.assertEqual(summary["counts"]["failed"], 1)
        self.assertEqual(summary["counts"]["skipped"], 1)
        self.assertEqual(summary["counts"]["notapplicable"], 1)

    def test_compliance_ignores_skipped_and_not_applicable(self) -> None:
        # 1 passed of 2 scored controls = 50.0%
        summary = parse_baseline.summarise(self.rows)
        self.assertEqual(summary["compliance_percent"], 50.0)

    def test_zero_scored_controls_does_not_divide_by_zero(self) -> None:
        summary = parse_baseline.summarise([{"_control": "a", "_status": "Skipped"}])
        self.assertEqual(summary["compliance_percent"], 0.0)

    def test_groups_by_category(self) -> None:
        summary = parse_baseline.summarise(self.rows)
        self.assertEqual(summary["by_category"]["BitLocker"]["passed"], 1)
        self.assertEqual(summary["by_category"]["BitLocker"]["failed"], 1)


class NormaliseTests(unittest.TestCase):
    def test_status_aliases(self) -> None:
        self.assertEqual(parse_baseline.normalise_status("PASS"), parse_baseline.PASSED)
        self.assertEqual(parse_baseline.normalise_status(" fail "), parse_baseline.FAILED)
        self.assertEqual(parse_baseline.normalise_status("N/A"), parse_baseline.NOT_APPLICABLE)
        self.assertEqual(parse_baseline.normalise_status("something odd"), parse_baseline.FAILED)


class LoadTests(unittest.TestCase):
    def _write(self, text: str) -> Path:
        handle = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8")
        handle.write(text)
        handle.close()
        return Path(handle.name)

    def test_loads_columns(self) -> None:
        rows = parse_baseline.load_rows(self._write(SAMPLE_CSV))
        self.assertEqual(len(rows), 6)
        summary = parse_baseline.summarise(rows)
        self.assertEqual(summary["counts"]["passed"], 3)
        self.assertEqual(summary["counts"]["failed"], 1)

    def test_comment_lines_are_ignored(self) -> None:
        rows = parse_baseline.load_rows(self._write(ANNOTATED_CSV))
        self.assertEqual(len(rows), 2)
        summary = parse_baseline.summarise(rows)
        self.assertEqual(summary["compliance_percent"], 50.0)

    def test_missing_status_column_raises(self) -> None:
        with self.assertRaises(ValueError):
            parse_baseline.load_rows(self._write("Control,Category\nx,y\n"))

    def test_render_markdown_states_source(self) -> None:
        summary = parse_baseline.summarise(parse_baseline.load_rows(self._write(SAMPLE_CSV)))
        report = parse_baseline.render_markdown(summary, "evidence/raw/wks01-before.csv")
        self.assertIn("evidence/raw/wks01-before.csv", report)


if __name__ == "__main__":
    unittest.main()
