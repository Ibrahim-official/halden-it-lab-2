#!/usr/bin/env python3
"""Unit tests for the P3 findings risk-scoring logic.

The logic lives in ``scripts/04-New-FindingsRegister.py``. Because the file name is numbered it
is not importable by name, so it is loaded by path here. Run with either:

    python3 scripts/tests/test_findings_risk.py
    python3 -m unittest discover -s scripts/tests

These tests exercise only pure functions and never touch the lab domain.
"""
from __future__ import annotations

import importlib.util
import json
import unittest
from datetime import date
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
SCRIPTS_DIR = TESTS_DIR.parent
PROJECT_DIR = SCRIPTS_DIR.parent
SCRIPT_PATH = SCRIPTS_DIR / "04-New-FindingsRegister.py"
RULES_PATH = PROJECT_DIR / "configs" / "p03-remediation-priority-rules.json"

_spec = importlib.util.spec_from_file_location("p03_findings_register", SCRIPT_PATH)
if _spec is None or _spec.loader is None:  # pragma: no cover - defensive
    raise ImportError(f"Cannot load {SCRIPT_PATH}")
register = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(register)


class ClampScaleTests(unittest.TestCase):
    def test_values_inside_range_are_unchanged(self) -> None:
        self.assertEqual(register.clamp_scale(3), 3)

    def test_low_and_high_are_clamped(self) -> None:
        self.assertEqual(register.clamp_scale(0), 1)
        self.assertEqual(register.clamp_scale(-4), 1)
        self.assertEqual(register.clamp_scale(9), 5)

    def test_non_numeric_defaults_to_low(self) -> None:
        self.assertEqual(register.clamp_scale(""), 1)
        self.assertEqual(register.clamp_scale(None), 1)
        self.assertEqual(register.clamp_scale("4"), 4)


class RiskScoreTests(unittest.TestCase):
    def test_minimum_and_maximum(self) -> None:
        self.assertEqual(register.risk_score(1, 1), 1)
        self.assertEqual(register.risk_score(5, 5), 25)

    def test_multiplication(self) -> None:
        self.assertEqual(register.risk_score(4, 5), 20)
        self.assertEqual(register.risk_score(3, 4), 12)

    def test_out_of_range_inputs_are_clamped(self) -> None:
        self.assertEqual(register.risk_score(0, 9), 5)
        self.assertEqual(register.risk_score(100, 100), 25)


class PriorityTests(unittest.TestCase):
    def test_band_boundaries(self) -> None:
        self.assertEqual(register.priority_for(25), "P0")
        self.assertEqual(register.priority_for(20), "P0")
        self.assertEqual(register.priority_for(19), "P1")
        self.assertEqual(register.priority_for(12), "P1")
        self.assertEqual(register.priority_for(11), "P2")
        self.assertEqual(register.priority_for(6), "P2")
        self.assertEqual(register.priority_for(5), "P3")
        self.assertEqual(register.priority_for(1), "P3")

    def test_domain_control_categories_escalate_one_band(self) -> None:
        self.assertEqual(register.priority_for(12, "privileged-access"), "P0")
        self.assertEqual(register.priority_for(12, "delegation"), "P0")
        self.assertEqual(register.priority_for(12, "credential-exposure"), "P0")

    def test_escalation_never_exceeds_p0(self) -> None:
        self.assertEqual(register.priority_for(25, "privileged-access"), "P0")

    def test_below_threshold_is_not_escalated(self) -> None:
        self.assertEqual(register.priority_for(11, "privileged-access"), "P2")
        self.assertEqual(register.priority_for(6, "delegation"), "P2")

    def test_other_categories_are_not_escalated(self) -> None:
        self.assertEqual(register.priority_for(12, "configuration"), "P1")


class TargetDateTests(unittest.TestCase):
    def test_target_days_per_priority(self) -> None:
        start = date(2026, 10, 2)
        self.assertEqual(register.target_date("P0", start), "2026-10-05")
        self.assertEqual(register.target_date("P1", start), "2026-10-16")
        self.assertEqual(register.target_date("P2", start), "2026-11-01")
        self.assertEqual(register.target_date("P3", start), "2026-12-31")


class RulesFileTests(unittest.TestCase):
    def test_rules_file_parses_and_has_expected_shape(self) -> None:
        self.assertTrue(RULES_PATH.exists(), f"missing rules file: {RULES_PATH}")
        with RULES_PATH.open(encoding="utf-8") as handle:
            rules = json.load(handle)
        self.assertIn("priority_bands", rules)
        self.assertIn("scoring", rules)
        priorities = [band["priority"] for band in rules["priority_bands"]]
        self.assertEqual(priorities, ["P0", "P1", "P2", "P3"])

    def test_load_rules_reads_the_file(self) -> None:
        rules = register.load_rules(RULES_PATH)
        self.assertEqual(len(rules["priority_bands"]), 4)

    def test_load_rules_falls_back_when_missing(self) -> None:
        rules = register.load_rules(PROJECT_DIR / "configs" / "does-not-exist.json")
        self.assertEqual(len(rules["priority_bands"]), 4)


class BuildRegisterTests(unittest.TestCase):
    def test_domain_control_finding_becomes_p0(self) -> None:
        findings = [{
            "ID": "P3-001",
            "Finding": "Tier 0 admin account can sign in to a workstation",
            "Tool": "manual",
            "Category": "privileged-access",
            "Likelihood": "4",
            "Impact": "5",
            "AffectedObjects": "G_Tier0_Admins",
            "BusinessImpact": "Domain takeover risk",
            "Remediation": "Apply deny-logon GPO",
            "Effort": "low",
            "Owner": "IT",
        }]
        rows = register.build_register(findings, start=date(2026, 10, 2))
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["RiskScore"], 20)
        self.assertEqual(rows[0]["Priority"], "P0")
        self.assertEqual(rows[0]["TargetDate"], "2026-10-05")
        self.assertEqual(set(rows[0].keys()), set(register.REGISTER_FIELDS))

    def test_empty_input_produces_no_rows(self) -> None:
        self.assertEqual(register.build_register([]), [])

    def test_display_column_order_matches_schema(self) -> None:
        self.assertEqual(register.REGISTER_FIELDS[0], "ID")
        self.assertEqual(register.REGISTER_FIELDS[-1], "Evidence")


if __name__ == "__main__":
    unittest.main(verbosity=2)
