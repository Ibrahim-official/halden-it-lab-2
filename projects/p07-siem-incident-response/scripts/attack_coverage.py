"""P7 detection-coverage roll-up for the Halden lab (library).

Turns (a) the ATT&CK mapping CSV and (b) a Wazuh alerts extract into a detection-coverage report.
It only ever reports what the alert file actually contains: a rule with no observed hit is marked
"no", never assumed to have fired (AGENTS.md rule R2).

The command-line entry point is ../11-AttackCoverageReport.py; the unit tests are in
../tests/test_attack_coverage.py.
"""

from __future__ import annotations

import csv
import dataclasses
import datetime as dt
import json
import logging
from pathlib import Path
from typing import Iterable, Iterator

LOG = logging.getLogger("attack_coverage")

# Rules below this ID are Wazuh built-ins; the Halden custom range is 100100-100199.
CUSTOM_RULE_MIN = 100100
CUSTOM_RULE_MAX = 100199


@dataclasses.dataclass(frozen=True)
class Technique:
    """One row of data/attack-mapping.csv."""

    technique_id: str
    technique_name: str
    tactic: str
    rule_id: str
    detection: str
    data_source: str
    runbook: str


@dataclasses.dataclass
class RuleResult:
    """What was actually observed for one rule in the alert extract."""

    rule_id: str
    count: int = 0
    first_seen: dt.datetime | None = None

    @property
    def fired(self) -> bool:
        return self.count > 0


def parse_timestamp(value: str) -> dt.datetime | None:
    """Parse a Wazuh ISO-8601 timestamp with a numeric offset, tolerantly.

    Wazuh writes timestamps such as ``2026-10-02T21:00:00.123+0000``. Returns ``None`` if the
    value is missing or in a shape we do not recognise, rather than raising: a single bad line in
    an alert file must not stop the report.
    """
    if not value:
        return None
    for fmt in ("%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            parsed = dt.datetime.strptime(value, fmt)
            return parsed.astimezone(dt.timezone.utc)
        except ValueError:
            continue
    return None


def severity_bucket(level: int) -> str:
    """Map a Wazuh rule level to a Halden severity band (see configs/alert-severity-triage.csv)."""
    if level >= 13:
        return "SEV1"
    if level >= 10:
        return "SEV2"
    if level >= 7:
        return "SEV3"
    return "info"


def load_mapping(path: Path) -> dict[str, Technique]:
    """Load the ATT&CK mapping keyed by rule id, skipping comment lines and blank lines."""
    mapping: dict[str, Technique] = {}
    with path.open("r", encoding="utf-8", newline="") as handle:
        for row in csv.DictReader(_non_comment_lines(handle)):
            rule_id = (row.get("rule_id") or "").strip()
            if not rule_id:
                continue
            mapping[rule_id] = Technique(
                technique_id=(row.get("technique_id") or "").strip(),
                technique_name=(row.get("technique_name") or "").strip(),
                tactic=(row.get("tactic") or "").strip(),
                rule_id=rule_id,
                detection=(row.get("detection") or "").strip(),
                data_source=(row.get("data_source") or "").strip(),
                runbook=(row.get("runbook") or "").strip(),
            )
    return mapping


def _non_comment_lines(lines: Iterable[str]) -> Iterator[str]:
    """Yield CSV lines with ``#`` comments and blank lines removed, so the CSV stays annotated."""
    for line in lines:
        if line.lstrip().startswith("#") or not line.strip():
            continue
        yield line


def iter_alerts(path: Path) -> Iterator[dict]:
    """Yield alert objects from a Wazuh JSON-lines extract, skipping unparseable lines."""
    with path.open("r", encoding="utf-8", errors="replace") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            try:
                yield json.loads(line)
            except json.JSONDecodeError:
                LOG.debug("Skipping unparseable alert line")
                continue


def summarise(
    alerts_path: Path,
    since: dt.datetime | None = None,
) -> dict[str, RuleResult]:
    """Count custom-rule hits in the alert extract, optionally ignoring alerts older than ``since``."""
    results: dict[str, RuleResult] = {}
    for alert in iter_alerts(alerts_path):
        rule = alert.get("rule", {})
        rule_id = str(rule.get("id", ""))
        if not rule_id.isdigit() or not (CUSTOM_RULE_MIN <= int(rule_id) <= CUSTOM_RULE_MAX):
            continue
        seen = parse_timestamp(alert.get("timestamp", ""))
        if since is not None and seen is not None and seen < since:
            continue
        bucket = results.setdefault(rule_id, RuleResult(rule_id=rule_id))
        bucket.count += 1
        if seen is not None and (bucket.first_seen is None or seen < bucket.first_seen):
            bucket.first_seen = seen
    return results


def coverage_rows(
    mapping: dict[str, Technique],
    results: dict[str, RuleResult],
) -> list[dict[str, str]]:
    """Join the mapping to the observed hits. ``validated`` is yes only when a hit was observed."""
    rows: list[dict[str, str]] = []
    for rule_id in sorted(mapping):
        technique = mapping[rule_id]
        result = results.get(rule_id)
        rows.append(
            {
                "rule_id": rule_id,
                "technique_id": technique.technique_id,
                "technique_name": technique.technique_name,
                "tactic": technique.tactic,
                "detection": technique.detection,
                "hits": str(result.count if result else 0),
                "validated": "yes" if (result and result.fired) else "no",
                "first_seen_utc": (
                    result.first_seen.strftime("%Y-%m-%d %H:%M:%S")
                    if result and result.first_seen
                    else ""
                ),
            }
        )
    return rows


def write_csv(rows: list[dict[str, str]], path: Path) -> None:
    """Write the coverage rows as CSV with a clear header."""
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        path.write_text("", encoding="utf-8")
        return
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def render_markdown(rows: list[dict[str, str]], window_description: str) -> str:
    """Render the coverage rows as a small markdown table for the portfolio."""
    validated = sum(1 for row in rows if row["validated"] == "yes")
    lines = [
        "# Halden P7 — detection validation result",
        "",
        f"Observation window: {window_description}. Generated from a real alert extract; a rule is "
        "`yes` only where a hit was actually observed.",
        "",
        f"**{validated}/{len(rows)} mapped rules fired in this window.**",
        "",
        "| Rule | ATT&CK | Detection | Hits | Validated | First seen (UTC) |",
        "|---|---|---|---|---|---|",
    ]
    for row in rows:
        lines.append(
            f"| {row['rule_id']} | {row['technique_id']} | {row['detection']} | {row['hits']} "
            f"| {row['validated']} | {row['first_seen_utc']} |"
        )
    lines.append("")
    lines.append("A rule that did not fire is a result to investigate (tune or re-test), not a failure to hide.")
    return "\n".join(lines)
