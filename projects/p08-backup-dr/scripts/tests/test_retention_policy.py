#!/usr/bin/env python3
"""Unit tests for the P8 retention-policy calculator.

Covers the `forget_arguments()` output and the `oldest_restore_point_days()` / immutability-floor
checks that protect the business's promised recovery window.

Run with pytest (``pytest scripts/tests``) or directly (``python3 scripts/tests/test_retention_policy.py``).
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "lib"))

from retention_policy import (  # noqa: E402  (import after sys.path tweak)
    DEFAULT_POLICY,
    Tier,
    audit,
    parse_policy,
)


class TestForgetArguments(unittest.TestCase):
    def test_tier1_flags_in_restic_order(self) -> None:
        tier = parse_policy(DEFAULT_POLICY)["tier1"]
        self.assertEqual(
            tier.forget_arguments(),
            "--keep-hourly 24 --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune",
        )

    def test_tier0_has_no_hourly(self) -> None:
        tier = parse_policy(DEFAULT_POLICY)["tier0"]
        self.assertNotIn("--keep-hourly", tier.forget_arguments())

    def test_yearly_appears_when_configured(self) -> None:
        tier = Tier("custom", {"daily": 7, "yearly": 3}, 30, 30)
        self.assertIn("--keep-yearly 3", tier.forget_arguments())

    def test_empty_policy_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            Tier("empty", {}, 30, 30).forget_arguments()

    def test_negative_retention_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            parse_policy({"bad": {"daily": -1}})


class TestReach(unittest.TestCase):
    def test_monthly_dominates_daily(self) -> None:
        tier = parse_policy(DEFAULT_POLICY)["tier1"]  # 12 monthly -> ~360 days
        self.assertEqual(tier.oldest_restore_point_days(), 360)

    def test_daily_only_policy(self) -> None:
        self.assertEqual(Tier("t", {"daily": 30}, 30, 30).oldest_restore_point_days(), 30)

    def test_hourly_only_reaches_one_day(self) -> None:
        self.assertEqual(Tier("t", {"hourly": 24}, 1, 1).oldest_restore_point_days(), 1)

    def test_weekly_multiplies_by_seven(self) -> None:
        self.assertEqual(Tier("t", {"weekly": 8}, 30, 30).oldest_restore_point_days(), 56)

    def test_yearly_multiplies_by_365(self) -> None:
        self.assertEqual(Tier("t", {"yearly": 2}, 30, 30).oldest_restore_point_days(), 730)


class TestAudit(unittest.TestCase):
    def test_default_halden_policy_is_consistent(self) -> None:
        self.assertEqual(audit(parse_policy(DEFAULT_POLICY)), [])

    def test_short_retention_warns(self) -> None:
        warnings = audit(parse_policy({"tier1": {"daily": 3, "immutable_floor_days": 30, "recovery_window_days": 30}}))
        self.assertEqual(len(warnings), 1)
        self.assertIn("retention reaches only 3d", warnings[0])

    def test_short_immutable_floor_warns(self) -> None:
        warnings = audit(parse_policy({"tier1": {"daily": 30, "monthly": 12, "immutable_floor_days": 7, "recovery_window_days": 30}}))
        self.assertEqual(len(warnings), 1)
        self.assertIn("immutable floor", warnings[0])

    def test_both_problems_produce_two_warnings(self) -> None:
        warnings = audit(parse_policy({"tier1": {"daily": 2, "immutable_floor_days": 2, "recovery_window_days": 30}}))
        self.assertEqual(len(warnings), 2)

    def test_retention_meets_window_boundary(self) -> None:
        tier = Tier("t", {"daily": 30}, 30, 30)
        self.assertTrue(tier.retention_meets_recovery_window())
        self.assertTrue(tier.immutable_floor_ok())


class TestParsePolicy(unittest.TestCase):
    def test_ignores_unknown_keys(self) -> None:
        tiers = parse_policy({"tier1": {"daily": 14, "note": "ignored", "immutable_floor_days": 30}})
        self.assertEqual(tiers["tier1"].keep, {"daily": 14})

    def test_defaults_immutable_and_window_to_zero(self) -> None:
        tier = parse_policy({"tier1": {"daily": 14}})["tier1"]
        self.assertEqual(tier.immutable_floor_days, 0)
        self.assertEqual(tier.recovery_window_days, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
