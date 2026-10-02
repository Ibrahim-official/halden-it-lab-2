#!/usr/bin/env python3
"""Turn normalised P3 assessment findings into a risk-scored findings register (CSV).

What this is
------------
P3 assesses Active Directory with PingCastle, Purple Knight and BloodHound CE. Each tool
speaks its own format, so this script takes a *normalised* findings CSV (one row per finding,
with a 1-5 likelihood and a 1-5 impact) and produces the register that the plan asks for:

    ID, Finding, Tool, Category, Likelihood, Impact, RiskScore, Priority, AffectedObjects,
    BusinessImpact, Remediation, Effort, Owner, TargetDate, Status, Evidence

Risk is Likelihood x Impact (1-25). Priority is P0-P3 from
``configs/p03-remediation-priority-rules.json``, with a one-band escalation for findings that
hand an attacker direct control of the domain (privileged-access, delegation,
credential-exposure) when the score is at least 12. Target dates come from the per-priority
target days in the same rules file.

Honesty
-------
This script invents nothing. With no ``--input`` it writes a header-only register, which is the
truthful state before the lab assessment has been run (AGENTS.md rule R2). Every row in a
produced register comes from a real tool finding that the owner pasted into the input CSV.

Usage
-----
    python3 04-New-FindingsRegister.py --input findings.csv --start-date 2026-10-05
    python3 04-New-FindingsRegister.py --input findings.csv --dry-run -v
    python3 04-New-FindingsRegister.py --input findings.csv --rules ../configs/p03-remediation-priority-rules.json

Run the unit tests with:
    python3 scripts/tests/test_findings_risk.py
"""
from __future__ import annotations

import argparse
import csv
import json
import logging
import sys
from datetime import date, timedelta
from pathlib import Path
from typing import Any, Iterable, Sequence

LOG = logging.getLogger("p03.findings")

SCRIPT_DIR = Path(__file__).resolve().parent
DEFAULT_RULES_PATH = SCRIPT_DIR.parent / "configs" / "p03-remediation-priority-rules.json"
DEFAULT_OUTPUT = SCRIPT_DIR.parent / "evidence" / "raw" / "p03-findings-register.csv"

REGISTER_FIELDS: tuple[str, ...] = (
    "ID",
    "Finding",
    "Tool",
    "Category",
    "Likelihood",
    "Impact",
    "RiskScore",
    "Priority",
    "AffectedObjects",
    "BusinessImpact",
    "Remediation",
    "Effort",
    "Owner",
    "TargetDate",
    "Status",
    "Evidence",
)

INPUT_FIELDS: tuple[str, ...] = (
    "ID",
    "Finding",
    "Tool",
    "Category",
    "Likelihood",
    "Impact",
    "AffectedObjects",
    "BusinessImpact",
    "Remediation",
    "Effort",
    "Owner",
)

# Embedded fallback so the scoring logic is testable without the rules file. Kept in step with
# configs/p03-remediation-priority-rules.json.
DEFAULT_RULES: dict[str, Any] = {
    "scoring": {"method": "likelihood times impact"},
    "priority_bands": [
        {"min_score": 20, "priority": "P0", "target_days": 3, "label": "Critical - contain first"},
        {"min_score": 12, "priority": "P1", "target_days": 14, "label": "High - fix this iteration"},
        {"min_score": 6, "priority": "P2", "target_days": 30, "label": "Medium - planned work"},
        {"min_score": 1, "priority": "P3", "target_days": 90, "label": "Low - backlog or risk-accept"},
    ],
    "category_escalation": {
        "categories": ["privileged-access", "delegation", "credential-exposure"],
        "escalate_when_score_at_least": 12,
        "maximum_priority": "P0",
    },
}

PRIORITY_ORDER: tuple[str, ...] = ("P0", "P1", "P2", "P3")


def clamp_scale(value: Any, low: int = 1, high: int = 5) -> int:
    """Coerce any input to an integer inside the 1-5 risk scale."""
    try:
        number = int(value)
    except (TypeError, ValueError):
        number = low
    return max(low, min(high, number))


def risk_score(likelihood: Any, impact: Any) -> int:
    """Return Likelihood x Impact on the 1-25 scale, clamping both inputs to 1-5."""
    return clamp_scale(likelihood) * clamp_scale(impact)


def priority_for(score: int, category: str = "", rules: dict[str, Any] | None = None) -> str:
    """Map a risk score (and category) to a P0-P3 priority."""
    active = rules or DEFAULT_RULES
    bands = sorted(active["priority_bands"], key=lambda band: band["min_score"], reverse=True)

    priority = PRIORITY_ORDER[-1]
    for band in bands:
        if score >= band["min_score"]:
            priority = band["priority"]
            break

    escalation = active.get("category_escalation", {})
    in_domain_control = str(category).strip().lower() in {
        str(item).lower() for item in escalation.get("categories", [])
    }
    if in_domain_control and score >= escalation.get("escalate_when_score_at_least", 12):
        index = max(PRIORITY_ORDER.index(priority) - 1, 0)  # one band towards P0
        priority = PRIORITY_ORDER[index]
    return priority


def target_date(priority: str, start: date, rules: dict[str, Any] | None = None) -> str:
    """Return the ISO target date for a priority, using the rules' target_days."""
    active = rules or DEFAULT_RULES
    days = 90
    for band in active["priority_bands"]:
        if band["priority"] == priority:
            days = int(band["target_days"])
            break
    return (start + timedelta(days=days)).isoformat()


def load_rules(path: Path) -> dict[str, Any]:
    """Load the remediation-priority rules file, falling back to the embedded rules."""
    try:
        with path.open(encoding="utf-8") as handle:
            return json.load(handle)
    except FileNotFoundError:
        LOG.warning("rules file %s not found; using embedded defaults", path)
        return DEFAULT_RULES


def _meaningful_lines(handle: Iterable[str]) -> list[str]:
    """Drop '#' comment lines and blank lines so config-style CSVs parse cleanly."""
    return [line for line in handle if line.strip() and not line.lstrip().startswith("#")]


def read_findings(path: Path) -> list[dict[str, str]]:
    """Read a normalised findings CSV, ignoring comment and blank lines."""
    with path.open(encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(_meaningful_lines(handle))
        rows = [{key: (value or "").strip() for key, value in row.items()} for row in reader]
    LOG.info("read %d candidate finding(s) from %s", len(rows), path)
    return rows


def build_register(
    findings: Sequence[dict[str, str]],
    rules: dict[str, Any] | None = None,
    start: date | None = None,
) -> list[dict[str, Any]]:
    """Score findings and return register rows in the schema order."""
    active = rules or DEFAULT_RULES
    start_date = start or date.today()
    rows: list[dict[str, Any]] = []
    for index, finding in enumerate(findings, start=1):
        likelihood = clamp_scale(finding.get("Likelihood"))
        impact = clamp_scale(finding.get("Impact"))
        score = risk_score(likelihood, impact)
        category = finding.get("Category", "")
        priority = priority_for(score, category, active)
        row: dict[str, Any] = {
            "ID": finding.get("ID") or f"P3-{index:03d}",
            "Finding": finding.get("Finding", ""),
            "Tool": finding.get("Tool", ""),
            "Category": category,
            "Likelihood": likelihood,
            "Impact": impact,
            "RiskScore": score,
            "Priority": priority,
            "AffectedObjects": finding.get("AffectedObjects", ""),
            "BusinessImpact": finding.get("BusinessImpact", ""),
            "Remediation": finding.get("Remediation", ""),
            "Effort": finding.get("Effort", ""),
            "Owner": finding.get("Owner", ""),
            "TargetDate": target_date(priority, start_date, active),
            "Status": finding.get("Status", "open"),
            "Evidence": finding.get("Evidence", "pending"),
        }
        rows.append(row)
    LOG.info("scored %d finding(s)", len(rows))
    return rows


def write_register(rows: Sequence[dict[str, Any]], path: Path, dry_run: bool = False) -> None:
    """Write the register CSV, or log what would be written when dry-running."""
    if dry_run:
        LOG.info("dry-run: would write %d row(s) to %s", len(rows), path)
        for row in rows:
            LOG.debug("dry-run row: %s", row)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(REGISTER_FIELDS), extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    LOG.info("wrote %d row(s) to %s", len(rows), path)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Score normalised AD assessment findings into the P3 findings register.",
        formatter_class=argparse.ArgumentDefaultsHelpFormatter,
    )
    parser.add_argument("--input", type=Path, default=None,
                        help="normalised findings CSV; omit to produce a header-only register")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT,
                        help="where to write the register CSV")
    parser.add_argument("--rules", type=Path, default=DEFAULT_RULES_PATH,
                        help="remediation-priority rules file")
    parser.add_argument("--start-date", type=lambda value: date.fromisoformat(value),
                        default=date.today(), help="date used to calculate target dates (YYYY-MM-DD)")
    parser.add_argument("--dry-run", action="store_true",
                        help="score and report without writing the register")
    parser.add_argument("-v", "--verbose", action="store_true", help="verbose logging")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(message)s",
    )

    rules = load_rules(args.rules)
    findings: list[dict[str, str]] = []
    if args.input is not None:
        if not args.input.exists():
            LOG.error("input file not found: %s", args.input)
            return 2
        findings = read_findings(args.input)
    else:
        LOG.warning("no --input given: producing a header-only register "
                    "(the honest state before the lab assessment has run)")

    rows = build_register(findings, rules, args.start_date)
    write_register(rows, args.output, args.dry_run)
    if not args.dry_run:
        counts: dict[str, int] = {}
        for row in rows:
            counts[row["Priority"]] = counts.get(row["Priority"], 0) + 1
        LOG.info("priority counts: %s", counts or "none")
    return 0


if __name__ == "__main__":
    sys.exit(main())
