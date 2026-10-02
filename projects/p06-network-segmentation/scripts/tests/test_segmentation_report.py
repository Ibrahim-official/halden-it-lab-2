"""Unit tests for the P6 segmentation report tool.

These tests run without the lab: they exercise the classification logic and the parsing with small
synthetic fixtures, so a bug in the report tooling is caught before it can misreport a real run.

Run with either::

    python3 -m pytest scripts/tests -q
    python3 -m unittest discover -s scripts/tests -v
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

# Make scripts/report importable regardless of where the tests are run from.
REPORT_DIR = Path(__file__).resolve().parent.parent / "report"
sys.path.insert(0, str(REPORT_DIR))

import segmentation_report as sr  # noqa: E402  (import after sys.path setup)

HEADER = ("test_id,source_zone,source_host,destination,port,expected,observed,result,checked_at\n")

SAMPLE_CSV = (
    "# P6 segmentation results - synthetic fixture for tests\n"
    + HEADER
    + "T-01,USERS-HQ,ws01,192.168.10.20,445,open,open,PASS,2026-01-01T00:00:00Z\n"
    + "T-02,USERS-HQ,ws01,192.168.40.10,3389,blocked,filtered,PASS,2026-01-01T00:00:01Z\n"
    + "T-03,USERS-HQ,ws01,192.168.40.10,445,blocked,open,FAIL,2026-01-01T00:00:02Z\n"
    + "T-04,GUEST,guesta,192.168.10.10,445,blocked,unreachable,PASS,2026-01-01T00:00:03Z\n"
)

# A results row whose PASS verdict has been tampered with. The report must recompute it.
TAMPERED_CSV = (
    HEADER
    + "T-09,GUEST,guesta,192.168.10.10,445,blocked,open,PASS,2026-01-01T00:00:04Z\n"
)


class ClassifyTests(unittest.TestCase):
    def test_expected_open_and_observed_open_passes(self) -> None:
        self.assertEqual(sr.classify("open", "open"), "PASS")

    def test_expected_open_and_observed_filtered_fails(self) -> None:
        self.assertEqual(sr.classify("open", "filtered"), "FAIL")

    def test_expected_blocked_accepts_filtered(self) -> None:
        self.assertEqual(sr.classify("blocked", "filtered"), "PASS")

    def test_expected_blocked_accepts_closed_and_unreachable(self) -> None:
        self.assertEqual(sr.classify("blocked", "closed"), "PASS")
        self.assertEqual(sr.classify("blocked", "unreachable"), "PASS")

    def test_expected_blocked_rejects_open(self) -> None:
        self.assertEqual(sr.classify("blocked", "open"), "FAIL")

    def test_expected_and_observed_are_case_insensitive(self) -> None:
        self.assertEqual(sr.classify("OPEN", "Open"), "PASS")
        self.assertEqual(sr.classify("Blocked", "FILTERED"), "PASS")


class ParseTests(unittest.TestCase):
    def _write(self, text: str) -> Path:
        tmp = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8")
        tmp.write(text)
        tmp.close()
        return Path(tmp.name)

    def test_comments_and_header_are_skipped(self) -> None:
        rows = sr.parse_results(self._write(SAMPLE_CSV))
        self.assertEqual(len(rows), 4)
        self.assertEqual(rows[0].test_id, "T-01")

    def test_foreign_csv_is_ignored(self) -> None:
        path = self._write("name,count\nfoo,1\n")
        self.assertEqual(sr.parse_results(path), [])

    def test_checked_at_is_carried_through(self) -> None:
        rows = sr.parse_results(self._write(SAMPLE_CSV))
        self.assertTrue(rows[0].checked_at.startswith("2026-01-01"))


class SummariseTests(unittest.TestCase):
    def _write(self, text: str) -> Path:
        tmp = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8")
        tmp.write(text)
        tmp.close()
        return Path(tmp.name)

    def test_counts_per_zone(self) -> None:
        rows = sr.parse_results(self._write(SAMPLE_CSV))
        summaries = sr.summarise(rows)
        self.assertEqual(summaries["USERS-HQ"].total, 3)
        self.assertEqual(summaries["USERS-HQ"].passed, 2)
        self.assertEqual(summaries["USERS-HQ"].failed, 1)
        self.assertEqual(summaries["USERS-HQ"].ratio, "2/3")
        self.assertEqual(summaries["GUEST"].ratio, "1/1")

    def test_failure_is_recorded_with_its_row(self) -> None:
        rows = sr.parse_results(self._write(SAMPLE_CSV))
        summaries = sr.summarise(rows)
        failures = summaries["USERS-HQ"].failures
        self.assertEqual(len(failures), 1)
        self.assertEqual(failures[0].test_id, "T-03")

    def test_tampered_pass_is_recomputed(self) -> None:
        rows = sr.parse_results(self._write(TAMPERED_CSV))
        summaries = sr.summarise(rows)
        self.assertEqual(summaries["GUEST"].failed, 1)
        self.assertEqual(summaries["GUEST"].ratio, "0/1")


class RenderTests(unittest.TestCase):
    def _write(self, text: str) -> Path:
        tmp = tempfile.NamedTemporaryFile("w", suffix=".csv", delete=False, encoding="utf-8")
        tmp.write(text)
        tmp.close()
        return Path(tmp.name)

    def test_empty_run_says_not_measured(self) -> None:
        report = sr.render_markdown({}, 0)
        self.assertIn("No results yet", report)

    def test_report_states_the_overall_ratio(self) -> None:
        rows = sr.parse_results(self._write(SAMPLE_CSV))
        report = sr.render_markdown(sr.summarise(rows), len(rows))
        self.assertIn("3/4", report)

    def test_report_lists_the_failure(self) -> None:
        rows = sr.parse_results(self._write(SAMPLE_CSV))
        report = sr.render_markdown(sr.summarise(rows), len(rows))
        self.assertIn("T-03", report)


class CliTests(unittest.TestCase):
    def test_dry_run_writes_nothing_and_returns_zero(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            results = Path(tmp) / "results"
            results.mkdir()
            (results / "p06-ph6-segmentation-results-ws01.csv").write_text(SAMPLE_CSV, encoding="utf-8")
            out = Path(tmp) / "out"
            code = sr.main(["--results", str(results), "--out", str(out), "--dry-run"])
            self.assertEqual(code, 0)
            self.assertFalse(out.exists())

    def test_missing_directory_returns_two(self) -> None:
        code = sr.main(["--results", "/nonexistent-p6-path"])
        self.assertEqual(code, 2)

    def test_real_run_writes_report_and_matrix(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            results = Path(tmp) / "results"
            results.mkdir()
            (results / "p06-ph6-segmentation-results-ws01.csv").write_text(SAMPLE_CSV, encoding="utf-8")
            out = Path(tmp) / "out"
            code = sr.main(["--results", str(results), "--out", str(out)])
            self.assertEqual(code, 0)
            self.assertTrue((out / "p06-segmentation-report.md").is_file())
            matrix = out / "p06-segmentation-verification-matrix.csv"
            self.assertTrue(matrix.is_file())
            self.assertIn("USERS-HQ", matrix.read_text(encoding="utf-8"))


if __name__ == "__main__":
    unittest.main()
