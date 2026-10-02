"""Unit tests for the P7 detection-coverage library (scripts/attack_coverage.py).

Run with:  python3 -m pytest projects/p07-siem-incident-response/scripts/tests/
   or:     python3 -m unittest discover -s projects/p07-siem-incident-response/scripts/tests

The tests exercise the pure logic only: mapping parsing, timestamp handling, severity bucketing
and the rule that "a rule is validated only if a hit was observed". No lab or network is used.
"""

from __future__ import annotations

import datetime as dt
import json
import sys
import tempfile
import unittest
from pathlib import Path

SCRIPTS_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPTS_DIR))

from attack_coverage import (  # noqa: E402  (path inserted above)
    coverage_rows,
    load_mapping,
    parse_timestamp,
    render_markdown,
    severity_bucket,
    summarise,
)

MAPPING_SAMPLE = """rule_id,technique_id,technique_name,tactic,detection,data_source,runbook
# a comment line that must be skipped
100100,T1098,Account Manipulation,Persistence,D1 privileged group add,Security 4728,privileged-group-change
100107,T1490,Inhibit System Recovery,Impact,D7 shadow copy deletion,Sysmon 1,ransomware-pre-encryption
"""


def _write(path: Path, text: str) -> Path:
    path.write_text(text, encoding="utf-8")
    return path


class ParseTimestampTests(unittest.TestCase):
    def test_parses_wazuh_format(self) -> None:
        parsed = parse_timestamp("2026-10-02T21:00:00.123+0000")
        self.assertIsNotNone(parsed)
        assert parsed is not None
        self.assertEqual(parsed.year, 2026)
        self.assertEqual(parsed.tzinfo, dt.timezone.utc)

    def test_returns_none_for_junk(self) -> None:
        self.assertIsNone(parse_timestamp(""))
        self.assertIsNone(parse_timestamp("not-a-date"))


class SeverityBucketTests(unittest.TestCase):
    def test_boundaries(self) -> None:
        self.assertEqual(severity_bucket(14), "SEV1")
        self.assertEqual(severity_bucket(13), "SEV1")
        self.assertEqual(severity_bucket(12), "SEV2")
        self.assertEqual(severity_bucket(10), "SEV2")
        self.assertEqual(severity_bucket(9), "SEV3")
        self.assertEqual(severity_bucket(7), "SEV3")
        self.assertEqual(severity_bucket(6), "info")


class LoadMappingTests(unittest.TestCase):
    def test_skips_comments_and_blanks(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = _write(Path(tmp) / "map.csv", MAPPING_SAMPLE)
            mapping = load_mapping(path)
        self.assertEqual(set(mapping), {"100100", "100107"})
        self.assertEqual(mapping["100100"].technique_id, "T1098")
        self.assertEqual(mapping["100107"].runbook, "ransomware-pre-encryption")


class SummariseTests(unittest.TestCase):
    def _alert(self, rule_id: str, ts: str, level: int = 12) -> str:
        return json.dumps(
            {"timestamp": ts, "rule": {"id": rule_id, "level": level, "description": "x"}}
        )

    def test_counts_custom_rules_within_window(self) -> None:
        now = dt.datetime.now(dt.timezone.utc)
        recent = (now - dt.timedelta(minutes=5)).strftime("%Y-%m-%dT%H:%M:%S.000+0000")
        old = (now - dt.timedelta(hours=5)).strftime("%Y-%m-%dT%H:%M:%S.000+0000")
        lines = [
            self._alert("100100", recent),
            self._alert("100100", recent),
            self._alert("100107", recent),
            self._alert("100100", old),      # outside the window
            self._alert("5712", recent),     # built-in rule, ignored
            "not json at all",               # must not raise
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = _write(Path(tmp) / "alerts.json", "\n".join(lines) + "\n")
            results = summarise(path, since=now - dt.timedelta(minutes=60))
        self.assertEqual(results["100100"].count, 2)
        self.assertEqual(results["100107"].count, 1)
        self.assertNotIn("5712", results)

    def test_no_alerts_yields_empty(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            path = _write(Path(tmp) / "alerts.json", "")
            self.assertEqual(summarise(path), {})


class CoverageRowsTests(unittest.TestCase):
    def test_not_fired_is_no_not_yes(self) -> None:
        with tempfile.TemporaryDirectory() as tmp:
            mapping = load_mapping(_write(Path(tmp) / "map.csv", MAPPING_SAMPLE))
            now = dt.datetime.now(dt.timezone.utc)
            alerts = _write(
                Path(tmp) / "alerts.json",
                json.dumps(
                    {
                        "timestamp": now.strftime("%Y-%m-%dT%H:%M:%S.000+0000"),
                        "rule": {"id": "100100", "level": 12, "description": "fired"},
                    }
                )
                + "\n",
            )
            results = summarise(alerts)
            rows = coverage_rows(mapping, results)
        by_rule = {row["rule_id"]: row for row in rows}
        self.assertEqual(by_rule["100100"]["validated"], "yes")
        self.assertEqual(by_rule["100100"]["hits"], "1")
        self.assertEqual(by_rule["100107"]["validated"], "no")
        self.assertEqual(by_rule["100107"]["hits"], "0")

    def test_markdown_counts_fired(self) -> None:
        rows = [
            {"rule_id": "100100", "technique_id": "T1098", "technique_name": "x", "tactic": "Persistence",
             "detection": "D1", "hits": "1", "validated": "yes", "first_seen_utc": "2026-10-02 21:00:00"},
            {"rule_id": "100107", "technique_id": "T1490", "technique_name": "y", "tactic": "Impact",
             "detection": "D7", "hits": "0", "validated": "no", "first_seen_utc": ""},
        ]
        report = render_markdown(rows, "last 60 minutes")
        self.assertIn("1/2 mapped rules fired", report)


class EndToEndTests(unittest.TestCase):
    def test_cli_dry_run_with_real_mapping(self) -> None:
        from importlib import util

        cli_path = SCRIPTS_DIR / "11-AttackCoverageReport.py"
        spec = util.spec_from_file_location("attack_coverage_cli", cli_path)
        assert spec and spec.loader
        module = util.module_from_spec(spec)
        spec.loader.exec_module(module)
        with tempfile.TemporaryDirectory() as tmp:
            alerts = _write(Path(tmp) / "alerts.json", "")
            rc = module.main(["--alerts", str(alerts), "--dry-run"])
        self.assertEqual(rc, 0)


if __name__ == "__main__":
    unittest.main()
