#!/usr/bin/env python3
"""Unit tests for the P10 repository-derived KPI collector.

Run from ``projects/p10-governance``:

    python3 scripts/tests/test_collect_kpis.py
    python3 -m pytest scripts/tests/test_collect_kpis.py   # if pytest is installed

These tests assert two things that matter for honesty:
  * a lab-dependent KPI never comes back with a number - it is always 'not measured';
  * every repository-derived KPI names a source, so a reader can reproduce it.
"""

from __future__ import annotations

import sys
import unittest
from datetime import date
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import collect_kpis as ck  # noqa: E402


class SnapshotTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.snapshot = ck.collect(as_of=date(2026, 10, 2))
        cls.by_id = {r.kpi_id: r for r in cls.snapshot.results}

    def test_snapshot_has_both_provenances(self) -> None:
        provenances = {r.derived_from for r in self.snapshot.results}
        self.assertEqual(provenances, {"repository", "lab"})

    def test_lab_kpis_are_never_numeric(self) -> None:
        for result in self.snapshot.results:
            if result.derived_from == "lab":
                self.assertEqual(result.value, ck.NOT_MEASURED, result.kpi_id)
                self.assertEqual(result.rag, "not measured", result.kpi_id)

    def test_every_repository_kpi_names_a_source(self) -> None:
        for result in self.snapshot.results:
            if result.derived_from == "repository":
                self.assertTrue(result.source, f"{result.kpi_id} has no source")

    def test_safeguard_count_is_fifty_six(self) -> None:
        workbook = ck.safeguard_workbook_counts()
        self.assertEqual(workbook["total"], 56)

    def test_no_safeguards_scored_yet(self) -> None:
        workbook = ck.safeguard_workbook_counts()
        self.assertEqual(workbook["scored_after"], 0)
        self.assertEqual(workbook["scored_before"], 0)

    def test_cis_percentage_reported_as_not_measured(self) -> None:
        self.assertEqual(self.by_id["KPI-22"].value, ck.NOT_MEASURED)

    def test_evidence_present_is_a_real_count(self) -> None:
        value = self.by_id["KPI-23"].value
        self.assertIsInstance(value, int)
        self.assertGreaterEqual(value, 0)
        self.assertLessEqual(value, 56)

    def test_change_register_count_matches_the_csv(self) -> None:
        rows = ck.read_csv(ck.CHANGE_LOG)
        self.assertEqual(self.by_id["KPI-18"].value, len(rows))

    def test_projects_measured_is_zero_without_a_lab(self) -> None:
        self.assertEqual(self.by_id["KPI-27"].value, 0)

    def test_change_types_are_the_expected_set(self) -> None:
        self.assertEqual(self.by_id["KPI-18"].value, 1)
        self.assertIn("normal", self.by_id["KPI-18"].note)

    def test_policy_register_is_ten_and_unsigned(self) -> None:
        self.assertEqual(self.by_id["KPI-26"].value, 0.0)
        self.assertIn("0 of 10 policies", self.by_id["KPI-26"].note)

    def test_dictionary_marks_provenance(self) -> None:
        payload = self.snapshot.as_dict()
        self.assertEqual(payload["derived_from"], "repository")
        self.assertTrue(payload["halden_is_fictional"])


class ProjectProbeTests(unittest.TestCase):
    def test_ten_project_folders(self) -> None:
        self.assertEqual(len(ck.project_folders()), 10)

    def test_showcase_status_is_a_known_value(self) -> None:
        for folder in ck.project_folders():
            self.assertIn(ck.read_showcase_status(folder), {"planned", "in-progress", "done", "unknown"})

    def test_p01_results_table_has_not_measured_rows(self) -> None:
        p01 = ck.PROJECTS_DIR / "p01-core-infrastructure"
        rows = ck.results_rows(p01)
        self.assertTrue(rows)
        self.assertTrue(all("not measured" in r.lower() for r in rows))

    def test_acceptance_tests_counted(self) -> None:
        total, not_run = ck.count_acceptance_tests()
        self.assertGreater(total, 0)
        self.assertLessEqual(not_run, total)
        # The large majority of acceptance tests target the lab and therefore read "not run".
        # A small number (for example the P5 Python unit tests and the synthetic-data generators)
        # are genuinely runnable without a lab, so this is a ratio check, not an equality.
        self.assertGreater(not_run, total * 0.9)

    def test_dod_items_present(self) -> None:
        count, items = ck.count_dod_items()
        self.assertGreater(count, 0)
        self.assertTrue(all(isinstance(i, str) for i in items))

    def test_script_count_positive(self) -> None:
        counts = ck.script_counts()
        self.assertGreater(counts["total"], 0)
        self.assertGreater(counts["projects_with_tests"], 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
