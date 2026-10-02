#!/usr/bin/env python3
"""Generate the SYNTHETIC HR source-of-truth export for the Halden lab (P2).

The P1 staff file is the single source of the 85 synthetic people:
``../p01-core-infrastructure/data/halden-staff.csv``. This generator adds only what P2 needs on top
of it - a stable ``ManagerID``, a ``Status`` and an ``EndDate`` - so the JML engine has a lifecycle
column to reconcile against. It deliberately does **not** duplicate the staff file as a second
hand-maintained copy: ``hr-export.csv`` is a generated artifact, not a source.

Everything here is synthetic and fictional. Nothing in this file is a measured value or real
personal data (AGENTS.md rule R2/R3).

Usage:
    python3 gen_hr_export.py                       # writes hr-export.csv beside this script
    python3 gen_hr_export.py --dry-run             # report only; writes nothing
    python3 gen_hr_export.py --mark-leaver 1042 --end-date 2026-10-02
"""
from __future__ import annotations

import argparse
import csv
import logging
import sys
from pathlib import Path
from typing import Dict, Iterable, List

LOG = logging.getLogger("gen_hr_export")

FIELDS = [
    "EmployeeID",
    "First",
    "Last",
    "Department",
    "Title",
    "ManagerID",
    "Status",
    "StartDate",
    "EndDate",
    "Office",
]

DEFAULT_SOURCE = Path(__file__).resolve().parent.parent.parent / "p01-core-infrastructure" / "data" / "halden-staff.csv"
DEFAULT_OUT = Path(__file__).resolve().parent / "hr-export.csv"


def load_staff(source: Path) -> List[Dict[str, str]]:
    """Read the P1 synthetic staff file, skipping blank lines."""
    with source.open(newline="", encoding="utf-8") as handle:
        return [row for row in csv.DictReader(handle) if row.get("EmployeeID")]


def manager_lookup(rows: Iterable[Dict[str, str]]) -> Dict[str, str]:
    """Map a ``first.last`` manager name to that manager's EmployeeID."""
    lookup: Dict[str, str] = {}
    for row in rows:
        sam = f"{row['First']}.{row['Last']}".lower()
        lookup[sam] = row["EmployeeID"]
    return lookup


def build_export(
    rows: List[Dict[str, str]],
    leavers: Iterable[str],
    end_date: str,
) -> List[Dict[str, str]]:
    """Add ManagerID, Status and EndDate to the staff rows."""
    lookup = manager_lookup(rows)
    leaver_ids = set(leavers)
    export: List[Dict[str, str]] = []
    for row in rows:
        manager_name = (row.get("Manager") or "").strip().lower()
        manager_id = lookup.get(manager_name, "")
        employee_id = row["EmployeeID"]
        export.append(
            {
                "EmployeeID": employee_id,
                "First": row["First"],
                "Last": row["Last"],
                "Department": row["Department"],
                "Title": row["Title"],
                "ManagerID": manager_id,
                "Status": "Leaver" if employee_id in leaver_ids else "Active",
                "StartDate": row.get("StartDate", ""),
                "EndDate": end_date if employee_id in leaver_ids else "",
                "Office": row.get("Office", ""),
            }
        )
    return export


def main(argv: List[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE, help="P1 synthetic staff CSV to derive from")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT, help="where to write the HR export")
    parser.add_argument("--mark-leaver", action="append", default=[], metavar="EMPLOYEEID", help="EmployeeID to mark as a Leaver (repeatable)")
    parser.add_argument("--end-date", default="", help="EndDate to write on marked leavers, e.g. 2026-10-02")
    parser.add_argument("--dry-run", action="store_true", help="report what would be written and exit")
    parser.add_argument("-v", "--verbose", action="store_true", help="debug logging")
    args = parser.parse_args(argv)

    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(levelname)s %(message)s")

    if not args.source.is_file():
        LOG.error("source staff file not found: %s", args.source)
        return 2

    staff = load_staff(args.source)
    export = build_export(staff, args.mark_leaver, args.end_date)
    leavers = sum(1 for row in export if row["Status"] == "Leaver")
    unresolved = sum(1 for row in export if not row["ManagerID"])

    LOG.info("source: %s (%d people)", args.source, len(staff))
    LOG.info("export: %d people, %d leaver(s), %d manager link(s) unresolved", len(export), leavers, unresolved)
    if unresolved:
        LOG.warning("unresolved manager links are usually the department head rows; check the source file")

    if args.dry_run:
        LOG.info("dry run: nothing written")
        return 0

    args.out.parent.mkdir(parents=True, exist_ok=True)
    with args.out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=FIELDS)
        writer.writeheader()
        writer.writerows(export)
    LOG.info("wrote %s", args.out)
    LOG.info("this file is SYNTHETIC and generated - do not edit it by hand")
    return 0


if __name__ == "__main__":
    sys.exit(main())
