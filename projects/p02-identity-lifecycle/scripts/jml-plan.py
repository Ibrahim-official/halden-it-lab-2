#!/usr/bin/env python3
"""Offline planner for the Halden joiner-mover-leaver engine (P2).

Reads the HR source-of-truth export, the role matrix and an AD snapshot, and writes the plan the
PowerShell engine (`01-Invoke-HaldenJML.ps1`) would apply - without connecting to a domain. Use it
to review a run, to explain a decision in an interview, or in CI to prove the rules with
`tests/test_jml_plan.py`.

Examples:
    python3 jml-plan.py --hr ../data/hr-export-sample.csv --matrix ../configs/role-matrix.csv \\
        --ad-snapshot ../data/ad-snapshot-sample.csv --dry-run

Everything here works on synthetic lab data. It makes no claims about a live directory.
"""
from __future__ import annotations

import argparse
import csv
import json
import logging
import sys
from dataclasses import asdict
from datetime import date, timedelta
from pathlib import Path
from typing import List

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))

import jml_plan  # noqa: E402  (path is set up above on purpose)

LOG = logging.getLogger("jml-plan")


def load_ad_snapshot(path: Path) -> List[jml_plan.AdUser]:
    """Load an AD snapshot CSV: EmployeeID,Sam,Department,Title,Enabled,Groups(semicolon list)."""
    users: List[jml_plan.AdUser] = []
    for row in csv.DictReader(jml_plan._data_lines(path)):  # noqa: SLF001 - deliberate reuse of the reader
        groups = frozenset(g.strip() for g in (row.get("Groups") or "").split(";") if g.strip())
        users.append(
            jml_plan.AdUser(
                employee_id=(row.get("EmployeeID") or "").strip(),
                sam=(row.get("Sam") or "").strip(),
                department=(row.get("Department") or "").strip(),
                title=(row.get("Title") or "").strip(),
                enabled=(row.get("Enabled") or "").strip().lower() in ("true", "yes", "1"),
                groups=groups,
            )
        )
    return users


def load_protected(path: Path) -> List[str]:
    if not path.is_file():
        return []
    return [
        line.strip()
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith("#")
    ]


def main(argv: List[str] | None = None) -> int:
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--hr", type=Path, default=here / ".." / "data" / "hr-export-sample.csv")
    parser.add_argument("--matrix", type=Path, default=here / ".." / "configs" / "role-matrix.csv")
    parser.add_argument("--ad-snapshot", type=Path, default=here / ".." / "data" / "ad-snapshot-sample.csv",
                        help="offline view of AD (EmployeeID,Sam,Department,Title,Enabled,Groups)")
    parser.add_argument("--protected", type=Path, default=here / ".." / "data" / "protected-accounts.txt")
    parser.add_argument("--today", default=None, help="override today's date (YYYY-MM-DD) for reproducible planning")
    parser.add_argument("--joiner-lead-days", type=int, default=7, help="how many days ahead a joiner is created")
    parser.add_argument("--circuit-breaker-percent", type=float, default=10.0,
                        help="abort if more leavers than this percentage of managed accounts")
    parser.add_argument("--out", type=Path, default=None, help="write the plan as JSON to this path")
    parser.add_argument("--dry-run", action="store_true", help="print the plan and write no file")
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(levelname)s %(message)s")

    for required in (args.hr, args.matrix, args.ad_snapshot):
        if not required.is_file():
            LOG.error("missing input file: %s", required)
            return 2

    try:
        people = jml_plan.load_hr(args.hr)
        matrix = jml_plan.load_role_matrix(args.matrix)
        ad_users = load_ad_snapshot(args.ad_snapshot)
    except ValueError as exc:
        LOG.error("input problem: %s", exc)
        return 2

    today = date.fromisoformat(args.today) if args.today else date.today()
    plan = jml_plan.build_plan(
        people,
        ad_users,
        matrix,
        today=today,
        joiner_lead_days=args.joiner_lead_days,
        protected=load_protected(args.protected),
        circuit_breaker_percent=args.circuit_breaker_percent,
    )

    LOG.info("plan for %s: %d action(s), %d skipped, %d orphan(s), %d protected",
             today.isoformat(), len(plan.actions), len(plan.skipped), len(plan.orphans), len(plan.protected))
    for action in plan.actions:
        if action.kind == "mover":
            LOG.info("MOVER  %s (%s) +%s -%s", action.sam, action.detail,
                     ",".join(action.add_groups) or "none", ",".join(action.remove_groups) or "none")
        else:
            LOG.info("%-6s %s (%s)", action.kind.upper(), action.sam, action.detail)
    if plan.orphans:
        LOG.warning("orphans (enabled AD accounts with no HR record, not changed automatically): %s",
                    ", ".join(plan.orphans))
    LOG.info("circuit breaker: %s", plan.breaker_detail)

    if plan.breaker_tripped:
        LOG.error("CIRCUIT BREAKER TRIPPED - the engine would abort this run and change nothing")

    payload = {
        "generated": today.isoformat(),
        "joinerLeadDays": args.joiner_lead_days,
        "circuitBreakerPercent": args.circuit_breaker_percent,
        "breakerTripped": plan.breaker_tripped,
        "breakerDetail": plan.breaker_detail,
        "snapshotTotal": plan.snapshot_total,
        "adTotal": plan.ad_total,
        "leaverCount": plan.leaver_count,
        "actions": [asdict(a) for a in plan.actions],
        "orphans": list(plan.orphans),
        "skipped": list(plan.skipped),
        "protected": list(plan.protected),
    }

    if args.dry_run or not args.out:
        LOG.info("dry run / no --out: %s", json.dumps(payload, indent=2))
        return 0

    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    LOG.info("wrote %s", args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
