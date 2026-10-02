#!/usr/bin/env python3
"""Unit tests for the P8 restore-verification report parser.

These tests run without a lab: they feed the parser the exact JSON shape that
``scripts/06-Test-BackupRestore.sh`` writes and check the history row and pass/fail decision.

Run with pytest (``pytest scripts/tests``) or directly (``python3 scripts/tests/test_restore_report.py``).
"""

from __future__ import annotations

import csv
import json
import sys
import unittest
from pathlib import Path

# Make scripts/lib importable when running this file directly.
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

from restore_report import (  # noqa: E402  (import after sys.path tweak)
    HISTORY_COLUMNS,
    RestoreResult,
    append_row,
    parse_result,
    read_history,
    summarise_rows,
)


def sample_payload(**overrides: object) -> dict:
    payload = {
        "date": "2026-10-11",
        "host": "FS01",
        "phase": "file-level",
        "files_tested": 20,
        "files_matched": 20,
        "mismatches": 0,
        "not_in_manifest": 0,
        "repo_check": "pass",
        "repo_detail": "no errors were found",
        "duration_seconds": 63,
        "result": "PASS",
    }
    payload.update(overrides)
    return payload


class TestParseResult(unittest.TestCase):
    def test_parses_a_full_payload(self) -> None:
        result = parse_result(sample_payload())
        self.assertEqual(result.host, "FS01")
        self.assertEqual(result.date, "2026-10-11")
        self.assertEqual(result.files_tested, 20)
        self.assertEqual(result.files_matched, 20)
        self.assertEqual(result.repo_check, "pass")
        self.assertEqual(result.duration_seconds, 63)

    def test_missing_counters_default_to_zero(self) -> None:
        result = parse_result({"date": "2026-10-11", "host": "DC01"})
        self.assertEqual(result.files_tested, 0)
        self.assertEqual(result.mismatches, 0)
        self.assertEqual(result.repo_check, "unknown")

    def test_rejects_missing_date_or_host(self) -> None:
        with self.assertRaises(ValueError):
            parse_result({"host": "FS01"})
        with self.assertRaises(ValueError):
            parse_result({"date": "2026-10-11"})

    def test_rejects_non_integer_counter(self) -> None:
        with self.assertRaises(ValueError):
            parse_result(sample_payload(files_tested="twenty"))

    def test_repo_check_is_normalised(self) -> None:
        self.assertEqual(parse_result(sample_payload(repo_check="PASS")).repo_check, "pass")


class TestPassDecision(unittest.TestCase):
    def test_all_files_matched_and_repo_pass_is_a_pass(self) -> None:
        self.assertTrue(parse_result(sample_payload()).is_pass())

    def test_a_single_mismatch_fails(self) -> None:
        result = parse_result(sample_payload(files_matched=19, mismatches=1))
        self.assertFalse(result.is_pass())

    def test_repo_check_failure_fails_even_when_files_match(self) -> None:
        self.assertFalse(parse_result(sample_payload(repo_check="fail")).is_pass())

    def test_unknown_repo_check_never_passes(self) -> None:
        payload = sample_payload()
        del payload["repo_check"]
        self.assertFalse(parse_result(payload).is_pass())

    def test_no_files_tested_is_not_a_pass(self) -> None:
        self.assertFalse(parse_result(sample_payload(files_tested=0, files_matched=0)).is_pass())

    def test_pass_rate(self) -> None:
        self.assertAlmostEqual(parse_result(sample_payload()).pass_rate, 1.0)
        self.assertAlmostEqual(parse_result(sample_payload(files_matched=15)).pass_rate, 0.75)

    def test_pass_rate_with_no_files_is_zero(self) -> None:
        self.assertEqual(RestoreResult("2026-10-11", "FS01", 0, 0, 0, "pass", 0).pass_rate, 0.0)


class TestToRow(unittest.TestCase):
    def test_row_has_exactly_the_history_columns(self) -> None:
        row = parse_result(sample_payload()).to_row()
        self.assertEqual(list(row.keys()), HISTORY_COLUMNS)

    def test_row_result_is_pass(self) -> None:
        self.assertEqual(parse_result(sample_payload()).to_row()["result"], "PASS")

    def test_row_result_is_fail_on_mismatch(self) -> None:
        self.assertEqual(parse_result(sample_payload(mismatches=1)).to_row()["result"], "FAIL")


class TestAppendAndRead(unittest.TestCase):
    def setUp(self) -> None:
        import tempfile

        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def _write_json(self, name: str, payload: dict) -> Path:
        path = self.root / name
        path.write_text(json.dumps(payload), encoding="utf-8")
        return path

    def test_append_creates_header_then_appends(self) -> None:
        csv_path = self.root / "history.csv"
        append_row(self._write_json("a.json", sample_payload()), csv_path)
        append_row(self._write_json("b.json", sample_payload(date="2026-10-18", mismatches=1)), csv_path)

        with csv_path.open(newline="", encoding="utf-8") as handle:
            rows = list(csv.DictReader(handle))
        self.assertEqual(len(rows), 2)
        self.assertEqual(rows[0]["result"], "PASS")
        self.assertEqual(rows[1]["result"], "FAIL")
        self.assertEqual(read_history(csv_path)[1]["host"], "FS01")

    def test_read_history_ignores_blank_lines(self) -> None:
        csv_path = self.root / "history.csv"
        append_row(self._write_json("a.json", sample_payload()), csv_path)
        with csv_path.open("a", encoding="utf-8") as handle:
            handle.write("\n")
        self.assertEqual(len(read_history(csv_path)), 1)

    def test_read_history_on_empty_file_is_empty(self) -> None:
        csv_path = self.root / "empty.csv"
        csv_path.write_text("", encoding="utf-8")
        self.assertEqual(read_history(csv_path), [])


class TestSummarise(unittest.TestCase):
    def test_empty_history(self) -> None:
        summary = summarise_rows([])
        self.assertEqual(summary.total, 0)
        self.assertEqual(summary.success_rate, 0.0)

    def test_counts_and_streak(self) -> None:
        rows = [
            {"host": "DC01", "result": "PASS"},
            {"host": "FS01", "result": "PASS"},
            {"host": "LNX01", "result": "FAIL"},
            {"host": "DC01", "result": "PASS"},
            {"host": "FS01", "result": "PASS"},
        ]
        summary = summarise_rows(rows)
        self.assertEqual(summary.total, 5)
        self.assertEqual(summary.passed, 4)
        self.assertEqual(summary.failed, 1)
        self.assertEqual(summary.consecutive_passes, 2)
        self.assertEqual(summary.longest_pass_streak, 2)
        self.assertAlmostEqual(summary.success_rate, 0.8)
        self.assertEqual(summary.hosts, {"DC01", "FS01", "LNX01"})

    def test_twelve_consecutive_passes(self) -> None:
        rows = [{"host": "FS01", "result": "PASS"} for _ in range(12)]
        summary = summarise_rows(rows)
        self.assertEqual(summary.consecutive_passes, 12)
        self.assertAlmostEqual(summary.success_rate, 1.0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
