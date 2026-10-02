"""Unit tests for the P5 risk-based prioritizer (scripts/05-prioritize.py).

Run either way — both work with no third-party packages installed:

    cd projects/p05-vuln-management
    python3 -m unittest discover -s scripts/tests -v
    python3 -m pytest scripts/tests -q          # if pytest happens to be installed

The scoring core (``tier``, ``sla_days``, ``priority_score``) is pure, so it is tested on its own.
A final integration test runs the whole pipeline over the bundled synthetic sample and pins the
row counts the README quotes.
"""
from __future__ import annotations

import importlib.util
import sys
import tempfile
import unittest
from datetime import date
from pathlib import Path

PROJECT_DIR = Path(__file__).resolve().parents[2]
SCRIPTS_DIR = PROJECT_DIR / "scripts"


def _load_prioritizer():
    """Import the numbered CLI script as a module so its pure functions can be tested."""
    spec = importlib.util.spec_from_file_location("p05_prioritize", SCRIPTS_DIR / "05-prioritize.py")
    assert spec and spec.loader, "could not load 05-prioritize.py"
    module = importlib.util.module_from_spec(spec)
    sys.modules["p05_prioritize"] = module
    spec.loader.exec_module(module)
    return module


p = _load_prioritizer()


class TierTests(unittest.TestCase):
    """The tier() rule order and every boundary between tiers."""

    def test_kev_on_exposed_host_is_p0(self) -> None:
        self.assertEqual(p.tier(True, True, 0.0, 1.0, 1), "P0")

    def test_kev_internal_is_p1_not_p0(self) -> None:
        self.assertEqual(p.tier(True, False, 0.0, 1.0, 1), "P1")

    def test_exposed_high_epss_without_kev_is_p1(self) -> None:
        self.assertEqual(p.tier(False, True, 0.5, 5.0, 1), "P1")

    def test_exposed_epss_boundary_just_below_threshold_falls_to_p2(self) -> None:
        # 0.4999 is below the 0.5 rule, but still above the 0.1 rule -> P2
        self.assertEqual(p.tier(False, True, 0.4999, 5.0, 1), "P2")

    def test_internal_high_epss_is_p2_even_without_kev_or_exposure(self) -> None:
        self.assertEqual(p.tier(False, False, 0.1, 5.0, 1), "P2")

    def test_critical_cvss_on_critical_asset_is_p2(self) -> None:
        self.assertEqual(p.tier(False, False, 0.0, 9.0, 3), "P2")

    def test_critical_cvss_on_non_critical_asset_is_only_p3(self) -> None:
        self.assertEqual(p.tier(False, False, 0.0, 9.0, 2), "P3")

    def test_high_cvss_is_p3(self) -> None:
        self.assertEqual(p.tier(False, False, 0.0, 7.0, 1), "P3")

    def test_cvss_just_below_high_is_p4(self) -> None:
        self.assertEqual(p.tier(False, False, 0.0, 6.9, 3), "P4")

    def test_nothing_elevated_is_p4(self) -> None:
        self.assertEqual(p.tier(False, False, 0.0, 0.0, 1), "P4")

    def test_tier_is_pure_and_repeatable(self) -> None:
        first = p.tier(True, True, 0.9, 9.8, 3)
        second = p.tier(True, True, 0.9, 9.8, 3)
        self.assertEqual(first, second)

    def test_custom_thresholds_change_the_result(self) -> None:
        strict = p.Rules(epss_critical=0.9)
        self.assertEqual(p.tier(False, True, 0.6, 5.0, 1, strict), "P2")
        self.assertEqual(p.tier(False, True, 0.95, 5.0, 1, strict), "P1")


class SlaAndScoreTests(unittest.TestCase):
    """SLA targets and the 0-100 priority score."""

    def test_sla_days_match_the_matrix(self) -> None:
        self.assertEqual([p.sla_days(t) for t in p.TIERS], [3, 7, 30, 60, 180])

    def test_score_is_capped_at_100(self) -> None:
        self.assertEqual(p.priority_score(True, True, True, 1.0, 10.0, 3), 100.0)

    def test_score_minimum_is_zero(self) -> None:
        self.assertEqual(p.priority_score(False, False, False, 0.0, 0.0, 1), 0.0)

    def test_score_clamps_out_of_range_inputs(self) -> None:
        # epss > 1, cvss > 10 and criticality > 3 must be clamped, not extrapolated.
        # Expected: epss 25 (clamped to 1.0) + exposure 15 + cvss 12 (clamped to 10) + criticality 8 (clamped to 3).
        self.assertEqual(p.priority_score(False, False, True, 5.0, 99.0, 9), 25.0 + 15.0 + 12.0 + 8.0)

    def test_kev_adds_the_largest_weight(self) -> None:
        with_kev = p.priority_score(True, False, False, 0.0, 0.0, 1)
        without = p.priority_score(False, False, False, 0.0, 0.0, 1)
        self.assertEqual(with_kev - without, 40.0)


class DeduplicateTests(unittest.TestCase):
    """Duplicate findings collapse to one remediation task."""

    def test_exact_duplicates_are_removed(self) -> None:
        items = [
            p.Finding("h", "CVE-2021-44228", 10.0, "http", 8080, "t", "s", date(2026, 9, 1)),
            p.Finding("h", "CVE-2021-44228", 10.0, "http", 8080, "t", "s", date(2026, 9, 2)),
        ]
        kept, removed = p.deduplicate(items)
        self.assertEqual(len(kept), 1)
        self.assertEqual(removed, 1)

    def test_same_cve_on_two_ports_is_not_a_duplicate(self) -> None:
        items = [
            p.Finding("h", "CVE-2022-0778", 7.5, "openssl", 443, "t", "s", date(2026, 9, 1)),
            p.Finding("h", "CVE-2022-0778", 7.5, "openssl", 8443, "t", "s", date(2026, 9, 1)),
        ]
        kept, removed = p.deduplicate(items)
        self.assertEqual((len(kept), removed), (2, 0))

    def test_no_cve_findings_dedupe_on_title(self) -> None:
        items = [
            p.Finding("h", "", 5.9, "tls", 443, "Weak ciphers", "s", date(2026, 9, 1)),
            p.Finding("h", "", 5.9, "tls", 443, "Weak ciphers", "s", date(2026, 9, 1)),
        ]
        kept, removed = p.deduplicate(items)
        self.assertEqual((len(kept), removed), (1, 1))


class RulesTests(unittest.TestCase):
    """Loading rules and overlaying config values."""

    def test_rules_overlay_keeps_defaults_for_absent_keys(self) -> None:
        rules = p.rules_from_mapping({"thresholds": {"epss_high": 0.2}})
        self.assertEqual(rules.epss_high, 0.2)
        self.assertEqual(rules.epss_critical, p.DEFAULT_RULES.epss_critical)
        self.assertEqual(rules.sla_days["P0"], 3)

    def test_rules_overlay_updates_weights(self) -> None:
        rules = p.rules_from_mapping({"scoring_weights": {"kev": 50}})
        self.assertEqual(rules.weights["kev"], 50.0)


class IoRoundTripTests(unittest.TestCase):
    """Parsing the CSVs and the enrichment JSON."""

    def test_findings_and_assets_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            findings_path = Path(tmp) / "f.csv"
            findings_path.write_text(
                "cve,cvss,host,service,port,title,solution,first_seen\n"
                "CVE-2021-44228,10.0,LNX01,http,8080,x,y,2026-09-01\n",
                encoding="utf-8",
            )
            assets_path = Path(tmp) / "a.csv"
            assets_path.write_text(
                "# comment line\n"
                "host,role,exposure,criticality,owner\n"
                "LNX01,app,internet,2,IT\n",
                encoding="utf-8",
            )
            findings = p.load_findings(findings_path)
            assets = p.load_assets(assets_path)
            self.assertEqual(findings[0].host, "lnx01")
            self.assertEqual(findings[0].cve, "CVE-2021-44228")
            self.assertEqual(assets["lnx01"].exposure, "internet")
            self.assertEqual(assets["lnx01"].criticality, 2)

    def test_enrichment_json_round_trip(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "e.json"
            path.write_text(
                '{"cves": {"CVE-2021-44228": {"kev": true, "ransomware": true, "epss": 0.97}}}',
                encoding="utf-8",
            )
            enrichment = p.load_enrichment(path)
            self.assertTrue(enrichment["CVE-2021-44228"].in_kev)
            self.assertEqual(enrichment["CVE-2021-44228"].epss, 0.97)


class SampleIntegrationTests(unittest.TestCase):
    """End-to-end run over the bundled synthetic sample; pins the README's numbers."""

    sample = PROJECT_DIR / "data" / "sample-scanner-export.csv"
    assets = PROJECT_DIR / "data" / "asset-criticality.csv"
    enrichment = PROJECT_DIR / "data" / "sample-enrichment.json"

    def setUp(self) -> None:
        for path in (self.sample, self.assets, self.enrichment):
            if not path.exists():
                self.skipTest(f"sample data missing: {path}")

    def test_sample_pipeline_counts(self) -> None:
        items, summary = p.build_work_list(
            p.load_findings(self.sample),
            p.load_assets(self.assets),
            p.load_enrichment(self.enrichment),
            as_of=date(2026, 10, 2),
        )
        self.assertEqual(summary["findings_raw"], 51)
        self.assertEqual(summary["findings_deduplicated"], 49)
        self.assertEqual(summary["duplicates_removed"], 2)
        self.assertEqual(summary["tier_counts"], {"P0": 2, "P1": 7, "P2": 17, "P3": 10, "P4": 13})
        self.assertEqual(summary["p0_p1_count"], 9)
        self.assertEqual(len(items), 49)
        # The list must be ranked P0 first, then by score.
        self.assertEqual(items[0].tier, "P0")
        self.assertGreaterEqual(items[0].priority_score, items[-1].priority_score)
        # MTTR is not invented from a single scan.
        self.assertEqual(summary["mttr"], "not measured")

    def test_first_item_is_the_kev_exposed_finding(self) -> None:
        items, _ = p.build_work_list(
            p.load_findings(self.sample),
            p.load_assets(self.assets),
            p.load_enrichment(self.enrichment),
            as_of=date(2026, 10, 2),
        )
        self.assertEqual(items[0].cve, "CVE-2021-44228")
        self.assertTrue(items[0].in_kev)
        self.assertEqual(items[0].exposure, "internet")


if __name__ == "__main__":
    unittest.main(verbosity=2)
