#!/usr/bin/env python3
"""Unit tests for the P10 CIS IG1 self-assessment logic.

Run from ``projects/p10-governance``:

    python3 scripts/tests/test_cis_assessment.py            # unittest
    python3 -m pytest scripts/tests/test_cis_assessment.py  # pytest, if installed

The tests use temporary CSV files, so they never depend on the state of the real workbook. They
prove the honesty rules: nothing is scored without evidence, and the percentage is withheld until
there are real scores.
"""

from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parent.parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

import cis_assessment as ca  # noqa: E402  (path set up above)

HEADER = (
    "safeguard_id,control_id,control_name,safeguard_title,asset_type,security_function,"
    "in_scope,before_status,after_status,evidence_source,owner,target_date,notes\n"
)
EVIDENCE_HEADER = (
    "safeguard_id,control_id,control_name,safeguard_title,description,"
    "halden_expected_evidence,source_projects,artifact_path,artifact_kind\n"
)


def write_csv(path: Path, header: str, rows: list[str]) -> Path:
    path.write_text(header + "\n".join(rows) + "\n", encoding="utf-8")
    return path


def safeguard_row(
    sid: str,
    control: str = "1",
    title: str = "A safeguard",
    before: str = "",
    after: str = "",
    evidence: str = "",
) -> str:
    return f"{sid},{control},Control,{title},Devices,Protect,yes,{before},{after},{evidence},,,"


class ParseStatusTests(unittest.TestCase):
    """The 0-3 scale is the only thing that may be written into a status cell."""

    def test_blank_means_not_scored(self) -> None:
        errors: list[str] = []
        self.assertIsNone(ca.parse_status("", "ctx", errors))
        self.assertEqual(errors, [])

    def test_valid_values_parse(self) -> None:
        errors: list[str] = []
        for value in range(4):
            self.assertEqual(ca.parse_status(str(value), "ctx", errors), value)
        self.assertEqual(errors, [])

    def test_out_of_scale_is_an_error(self) -> None:
        errors: list[str] = []
        self.assertIsNone(ca.parse_status("4", "ctx", errors))
        self.assertEqual(len(errors), 1)

    def test_non_numeric_is_an_error(self) -> None:
        errors: list[str] = []
        self.assertIsNone(ca.parse_status("high", "ctx", errors))
        self.assertEqual(len(errors), 1)


class AssessmentMathTests(unittest.TestCase):
    """Percentages and gaps must follow the documented formula."""

    def make(self, scores: list[int | None]) -> ca.Assessment:
        assessment = ca.Assessment()
        for index, score in enumerate(scores, start=1):
            assessment.safeguards.append(
                ca.Safeguard(
                    safeguard_id=f"1.{index}",
                    control_id="1",
                    control_name="Inventory",
                    title="t",
                    after_status=score,
                )
            )
        return assessment

    def test_no_scores_means_no_percentage(self) -> None:
        assessment = self.make([None, None])
        self.assertIsNone(assessment.percent("after"))
        self.assertIn("not measured", ca.console_summary(assessment))

    def test_full_marks_is_one_hundred_percent(self) -> None:
        assessment = self.make([3, 3])
        self.assertEqual(assessment.percent("after"), 100.0)

    def test_half_marks(self) -> None:
        assessment = self.make([3, 0])
        self.assertEqual(assessment.percent("after"), 50.0)

    def test_partial_scores_only_count_scored_rows(self) -> None:
        # Two scored rows (3 and 0) plus one unscored: the unscored row must not dilute the result.
        assessment = self.make([3, 0, None])
        self.assertEqual(assessment.percent("after"), 50.0)

    def test_gap_to_full(self) -> None:
        assessment = self.make([3, 2, 1])
        gaps = {s.after_status: s.gap_to_full for s in assessment.safeguards}
        self.assertEqual(gaps, {3: 0, 2: 1, 1: 2})
        self.assertEqual(len(assessment.open_gaps), 2)

    def test_control_percentage(self) -> None:
        assessment = self.make([3, 0])
        self.assertEqual(assessment.control_percent("1", "after"), 50.0)
        self.assertIsNone(assessment.control_percent("9", "after"))


class ValidationTests(unittest.TestCase):
    """The workbook rules that stop a generous score from being accepted."""

    def setUp(self) -> None:
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self) -> None:
        self.tmp.cleanup()

    def test_score_of_three_requires_evidence(self) -> None:
        safeguards = write_csv(
            self.root / "s.csv",
            HEADER,
            [safeguard_row("1.1", after="3", evidence="")],
        )
        assessment = ca.load_assessment(safeguards, self.root / "missing.csv")
        self.assertTrue(any("names no evidence source" in e for e in assessment.errors))

    def test_score_of_three_with_missing_evidence_file_is_rejected(self) -> None:
        """A path that does not resolve to a real file is not evidence."""
        safeguards = write_csv(
            self.root / "s.csv",
            HEADER,
            [safeguard_row("1.1", after="3", evidence="projects/nobody/here.png")],
        )
        assessment = ca.load_assessment(safeguards, self.root / "missing.csv")
        self.assertTrue(any("does not exist in the repository" in e for e in assessment.errors))

    def test_score_of_three_with_real_evidence_file_passes(self) -> None:
        """The shipped architecture diagram is a real file, so it is acceptable evidence."""
        safeguards = write_csv(
            self.root / "s.csv",
            HEADER,
            [
                safeguard_row(
                    "1.1",
                    after="3",
                    evidence="projects/p10-governance/evidence/public/p10-architecture.svg",
                )
            ],
        )
        assessment = ca.load_assessment(safeguards, self.root / "missing.csv")
        self.assertFalse(any("evidence" in e for e in assessment.errors))

    def test_evidence_map_alone_does_not_satisfy_the_evidence_rule(self) -> None:
        """An expected artifact path from the map is not proof; the score still needs a source."""
        safeguards = write_csv(
            self.root / "s.csv",
            HEADER,
            [safeguard_row("1.1", after="3", evidence="")],
        )
        evidence = write_csv(
            self.root / "e.csv",
            EVIDENCE_HEADER,
            [
                "1.1,1,Inventory,Detailed Asset Inventory,desc,GLPI reconciliation,P9,"
                "projects/p09-service-desk-cmdb/evidence/public/x.csv,csv-report"
            ],
        )
        assessment = ca.load_assessment(safeguards, evidence)
        self.assertTrue(any("names no evidence source" in e for e in assessment.errors))

    def test_score_of_three_with_evidence_is_accepted(self) -> None:
        safeguards = write_csv(
            self.root / "s.csv",
            HEADER,
            [safeguard_row("1.1", after="3", evidence="evidence/public/x.png")],
        )
        assessment = ca.load_assessment(safeguards, self.root / "missing.csv")
        self.assertFalse(any("names no evidence source" in e for e in assessment.errors))

    def test_unscored_workbook_is_not_a_scoring_error(self) -> None:
        safeguards = write_csv(self.root / "s.csv", HEADER, [safeguard_row("1.1")])
        assessment = ca.load_assessment(safeguards, self.root / "missing.csv")
        # A single-row fixture still trips the count check, but it must not trip the evidence rule.
        self.assertFalse(any("names no evidence source" in e for e in assessment.errors))
        self.assertIsNone(assessment.percent("after"))

    def test_unscored_full_workbook_has_no_errors(self) -> None:
        rows = [safeguard_row(f"{c}.1", control=str(c)) for c in [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 14, 15, 17]]
        # Pad to 56 with additional Control 14 rows so the count check passes.
        rows += [safeguard_row(f"14.{n}", control="14") for n in range(2, 43)]
        self.assertEqual(len(rows), 56)
        safeguards = write_csv(self.root / "s.csv", HEADER, rows)
        assessment = ca.load_assessment(safeguards, self.root / "missing.csv")
        self.assertEqual(assessment.errors, [])
        self.assertIsNone(assessment.percent("after"))

    def test_wrong_safeguard_count_is_flagged(self) -> None:
        safeguards = write_csv(self.root / "s.csv", HEADER, [safeguard_row("1.1")])
        assessment = ca.load_assessment(safeguards, self.root / "missing.csv")
        self.assertTrue(any("expected 56" in e for e in assessment.errors))

    def test_duplicate_ids_are_flagged(self) -> None:
        safeguards = write_csv(
            self.root / "s.csv",
            HEADER,
            [safeguard_row("1.1"), safeguard_row("1.1")],
        )
        assessment = ca.load_assessment(safeguards, self.root / "missing.csv")
        self.assertTrue(any("duplicate safeguard_id" in e for e in assessment.errors))

    def test_evidence_map_join(self) -> None:
        safeguards = write_csv(
            self.root / "s.csv",
            HEADER,
            [safeguard_row("1.1")],
        )
        evidence = write_csv(
            self.root / "e.csv",
            EVIDENCE_HEADER,
            [
                "1.1,1,Inventory,Detailed Asset Inventory,desc,GLPI reconciliation,P9,"
                "projects/p09-service-desk-cmdb/evidence/public/x.csv,csv-report"
            ],
        )
        assessment = ca.load_assessment(safeguards, evidence)
        self.assertEqual(assessment.safeguards[0].expected_evidence, "GLPI reconciliation")
        self.assertEqual(assessment.safeguards[0].artifact_path, "projects/p09-service-desk-cmdb/evidence/public/x.csv")

    def test_real_workbook_loads_clean(self) -> None:
        """The shipped workbook must load with 56 safeguards and no validation errors."""
        assessment = ca.load_assessment()
        self.assertEqual(assessment.total, 56)
        self.assertEqual(assessment.errors, [])
        self.assertIsNone(assessment.percent("after"))


class RealWorkbookTests(unittest.TestCase):
    """Properties the real, committed workbook must satisfy."""

    def setUp(self) -> None:
        self.assessment = ca.load_assessment()

    def test_total_is_fifty_six(self) -> None:
        self.assertEqual(self.assessment.total, 56)

    def test_nothing_is_scored_yet(self) -> None:
        # If this ever fails it means scores were entered, which is fine - but then the percentage
        # must be a real number, which the assertions below check.
        self.assertEqual(self.assessment.scored_after, 0)
        self.assertIsNone(self.assessment.percent("after"))

    def test_controls_present(self) -> None:
        controls = {s.control_id for s in self.assessment.safeguards}
        expected = {"1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11", "12", "14", "15", "17"}
        self.assertEqual(controls, expected)

    def test_control_14_has_the_most_safeguards(self) -> None:
        counts: dict[str, int] = {}
        for s in self.assessment.safeguards:
            counts[s.control_id] = counts.get(s.control_id, 0) + 1
        self.assertEqual(counts["14"], 8)
        self.assertEqual(max(counts, key=counts.get), "14")

    def test_controls_13_16_18_excluded(self) -> None:
        controls = {s.control_id for s in self.assessment.safeguards}
        for excluded in ("13", "16", "18"):
            self.assertNotIn(excluded, controls)

    def test_every_safeguard_is_in_scope(self) -> None:
        self.assertTrue(all(s.in_scope for s in self.assessment.safeguards))

    def test_report_says_not_scored(self) -> None:
        report = ca.render_report(self.assessment)
        self.assertIn("Not scored yet", report)
        self.assertIn("56", report)


if __name__ == "__main__":
    unittest.main(verbosity=2)
