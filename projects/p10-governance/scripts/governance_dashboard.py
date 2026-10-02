#!/usr/bin/env python3
"""Build the JSON that drives the static governance dashboard.

Applies to projects/p10-governance. The dashboard itself is a static HTML page (no backend, no live
systems - AGENTS.md Section 5.1); this script produces the data file it reads.

Output
  reports/governance-dashboard.json

The JSON is deliberately explicit about provenance: every tile carries a ``provenance`` of
``repository`` or ``not-measured``/``lab``, so the page can label it correctly and no unmeasured
number can leak onto the dashboard as if it were a lab result.

Exit codes
  0 success · 2 no KPI snapshot available
"""

from __future__ import annotations

import argparse
import json
import sys
from datetime import date
from pathlib import Path

from _common import (
    LOG,
    P10_DIR,
    configure_logging,
    parse_date,
    read_csv,
    write_text,
)

KPI_DEFS = P10_DIR / "configs" / "kpi-definitions.csv"
SAFEGUARDS = P10_DIR / "data" / "cis-ig1-safeguards.csv"
EVIDENCE_MAP = P10_DIR / "configs" / "cis-ig1-evidence-map.csv"
CHANGE_LOG = P10_DIR / "data" / "change-log.csv"
POLICY_REGISTER = P10_DIR / "data" / "policy-register.csv"
RISK_REGISTER = P10_DIR / "data" / "risk-register.csv"
TARGET = P10_DIR / "configs" / "cis-ig1-evidence-map.csv"


# --------------------------------------------------------------------------------------
# Panel builders
# --------------------------------------------------------------------------------------
def cis_panel() -> dict[str, object]:
    """The CIS IG1 panel: scores if scored, otherwise an honest 'not scored' state."""
    safeguards = read_csv(SAFEGUARDS) if SAFEGUARDS.is_file() else []
    scored_after = sum(1 for s in safeguards if (s.get("after_status") or "").strip() != "")
    scored_before = sum(1 for s in safeguards if (s.get("before_status") or "").strip() != "")
    control_counts: dict[str, int] = {}
    for s in safeguards:
        control_counts[s.get("control_id", "")] = control_counts.get(s.get("control_id", ""), 0) + 1
    return {
        "safeguard_count": len(safeguards),
        "scored_before": scored_before,
        "scored_after": scored_after,
        "percent_implemented": None if scored_after == 0 else "see reports/cis-ig1-assessment-*.md",
        "note": (
            "not scored yet - the assessment has not been run"
            if scored_after == 0
            else "percentages come from the latest CIS assessment report"
        ),
        "controls": [
            {"control_id": cid, "safeguards": count}
            for cid, count in sorted(control_counts.items(), key=lambda kv: int(kv[0]))
        ],
    }


def change_panel() -> dict[str, object]:
    """The change panel, from the register."""
    rows = read_csv(CHANGE_LOG) if CHANGE_LOG.is_file() else []
    by_type: dict[str, int] = {}
    unsigned = 0
    for row in rows:
        ctype = (row.get("change_type") or "untyped").strip() or "untyped"
        by_type[ctype] = by_type.get(ctype, 0) + 1
        if not (row.get("approver") or "").strip():
            unsigned += 1
    return {
        "total": len(rows),
        "by_type": by_type,
        "awaiting_approval": unsigned,
        "success_rate": "not measured",
        "emergency_share": "not measured (register too small to be meaningful)",
    }


def policy_panel() -> dict[str, object]:
    rows = read_csv(POLICY_REGISTER) if POLICY_REGISTER.is_file() else []
    approved = sum(1 for r in rows if (r.get("approval_date") or "").strip())
    return {
        "total": len(rows),
        "approved": approved,
        "acknowledged": "not measured",
        "items": [
            {
                "policy_id": r.get("policy_id", ""),
                "title": r.get("title", ""),
                "approved": bool((r.get("approval_date") or "").strip()),
            }
            for r in rows
        ],
    }


def risk_panel() -> dict[str, object]:
    rows = read_csv(RISK_REGISTER) if RISK_REGISTER.is_file() else []
    return {
        "open_risks": len(rows),
        "note": "register empty until real risks are assessed; methodology in business/p10-risk-register.md",
        "heatmap": [],
    }


def build_dashboard(snapshot_path: Path) -> dict[str, object]:
    snapshot = json.loads(snapshot_path.read_text(encoding="utf-8"))
    as_of = parse_date(str(snapshot.get("as_of", ""))) or date.today()
    kpis = snapshot.get("kpis", [])

    tiles: list[dict[str, object]] = []
    for kpi in kpis:
        value = kpi.get("value")
        provenance = "repository" if kpi.get("derived_from") == "repository" else "not-measured"
        tiles.append(
            {
                "id": kpi.get("kpi_id"),
                "label": kpi.get("name"),
                "value": "not measured" if provenance == "not-measured" else value,
                "unit": kpi.get("unit", ""),
                "target": kpi.get("target", ""),
                "rag": "not-measured" if provenance == "not-measured" else kpi.get("rag", "informational"),
                "provenance": provenance,
                "source": kpi.get("source", ""),
                "note": kpi.get("note", ""),
            }
        )

    return {
        "generated": as_of.isoformat(),
        "halden_is_fictional": True,
        "lab_executed": False,
        "headline": (
            "Build kits complete, lab execution pending. Tiles marked 'repository' are measured from "
            "this repository today; tiles marked 'not measured' need a lab run."
        ),
        "cis_ig1": cis_panel(),
        "changes": change_panel(),
        "policies": policy_panel(),
        "risks": risk_panel(),
        "tiles": tiles,
    }


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="governance_dashboard.py",
        description="Build the static governance dashboard data (JSON) from the KPI snapshot and the register files.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--snapshot", type=Path, default=None, help="KPI snapshot JSON (defaults to the newest)")
    parser.add_argument("--out", type=Path, default=P10_DIR / "reports" / "governance-dashboard.json")
    parser.add_argument("--json", action="store_true", help="print the dashboard JSON to stdout")
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser


def newest_snapshot(out_dir: Path) -> Path | None:
    candidates = sorted(out_dir.glob("kpi-snapshot-*.json"))
    return candidates[-1] if candidates else None


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    configure_logging(args.verbose)

    snapshot_path = args.snapshot or newest_snapshot(P10_DIR / "reports")
    if snapshot_path is None or not Path(snapshot_path).is_file():
        LOG.error("No KPI snapshot found. Run scripts/collect_kpis.py first.")
        return 2

    dashboard = build_dashboard(Path(snapshot_path))
    if args.json:
        print(json.dumps(dashboard, indent=2))
    else:
        repo_tiles = sum(1 for t in dashboard["tiles"] if t["provenance"] == "repository")
        print(f"Dashboard tiles: {len(dashboard['tiles'])} ({repo_tiles} repository-derived, {len(dashboard['tiles']) - repo_tiles} not measured)")
        print(f"CIS IG1: {dashboard['cis_ig1']['safeguard_count']} safeguards, {dashboard['cis_ig1']['scored_after']} scored")
        print(f"Changes: {dashboard['changes']['total']} · Policies: {dashboard['policies']['total']} ({dashboard['policies']['approved']} approved)")

    if args.dry_run:
        LOG.info("dry-run: would write %s", args.out)
        return 0
    write_text(Path(args.out), json.dumps(dashboard, indent=2) + "\n")
    if not args.json:
        print(f"\nDashboard data: {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
