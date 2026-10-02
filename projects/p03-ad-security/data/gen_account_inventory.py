#!/usr/bin/env python3
"""Generate the SYNTHETIC account/group inventory that P3 uses to plan admin tiering.

What this is
------------
The tiering work in P3 needs a written list of which accounts exist, who they belong to, and
which tier they should end up in. That list is **derived from the same synthetic staff file** used
by P1 (``../../p01-core-infrastructure/data/halden-staff.csv``) — this script references that file
and does not duplicate or copy it.

Everything produced here is **synthetic**. Halden Distribution Ltd. is a fictional company and no
real personal data is used (AGENTS.md rules R2/R3 and Section 4.6).

What it produces
----------------
``halden-account-inventory.csv`` with one row per planned account:

    Account, Type, DisplayName, Department, Title, AdminFor, ProposedTier,
    CurrentTier, Basis

  * Type = Standard is the person's daily-use account (no admin rights).
  * Type = Admin is the separate ``adm-t{tier}-first.last`` account, one per IT person.
  * Basis records *why* the tier was proposed, so the decision is auditable rather than assumed.

Usage
-----
    python3 gen_account_inventory.py
    python3 gen_account_inventory.py --dry-run
    python3 gen_account_inventory.py --staff-csv ../../p01-core-infrastructure/data/halden-staff.csv

The CurrentTier column is intentionally ``unassigned``: it is filled in from the lab only after
the accounts really exist and have been reviewed.
"""
from __future__ import annotations

import argparse
import csv
import logging
import sys
from pathlib import Path
from typing import Any, Sequence

LOG = logging.getLogger("p03.inventory")

DEFAULT_STAFF_CSV = Path(__file__).resolve().parent.parent.parent / "p01-core-infrastructure" / "data" / "halden-staff.csv"
DEFAULT_OUTPUT = Path(__file__).resolve().parent / "halden-account-inventory.csv"

FIELDS: tuple[str, ...] = (
    "Account",
    "Type",
    "DisplayName",
    "Department",
    "Title",
    "AdminFor",
    "ProposedTier",
    "CurrentTier",
    "Basis",
)

# Which tier a role's admin account belongs to, and why. Kept small and explicit so the tiering
# decision can be defended in a review.
ROLE_TIERS: dict[str, tuple[int, str]] = {
    "IT Manager": (0, "owns the domain, its controllers and the directory itself"),
    "Systems Administrator": (1, "administers member servers and their applications"),
    "IT Support Officer": (2, "administers workstations and user objects"),
}

# Roles that must never receive an admin account.
NO_ADMIN_ROLES = {"HR Officer", "Recruiter"}


def sam_for(row: dict[str, str]) -> str:
    return f"{row['First']}.{row['Last']}".lower()


def tier_for(title: str) -> tuple[int, str] | None:
    """Return (tier, basis) for a job title, or None when no admin account is planned."""
    if title in NO_ADMIN_ROLES:
        return None
    return ROLE_TIERS.get(title)


def build_inventory(staff_rows: Sequence[dict[str, str]]) -> list[dict[str, Any]]:
    """Turn synthetic staff rows into standard and admin account rows."""
    inventory: list[dict[str, Any]] = []
    for row in staff_rows:
        sam = sam_for(row)
        display = f"{row['First']} {row['Last']}"
        inventory.append({
            "Account": sam,
            "Type": "Standard",
            "DisplayName": display,
            "Department": row["Department"],
            "Title": row["Title"],
            "AdminFor": "-",
            "ProposedTier": "-",
            "CurrentTier": "unassigned",
            "Basis": "daily-use account; no administrative rights by design",
        })
        choice = tier_for(row["Title"])
        if choice is None:
            continue
        tier, basis = choice
        inventory.append({
            "Account": f"adm-t{tier}-{sam}",
            "Type": "Admin",
            "DisplayName": f"Admin Tier {tier} - {display}",
            "Department": row["Department"],
            "Title": row["Title"],
            "AdminFor": row["Title"],
            "ProposedTier": tier,
            "CurrentTier": "unassigned",
            "Basis": basis,
        })
    return inventory


def read_staff(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        raise FileNotFoundError(
            f"synthetic staff file not found: {path}\n"
            "P3 references the P1 synthetic file (halden-staff.csv); do not create a second copy."
        )
    with path.open(encoding="utf-8", newline="") as handle:
        return [dict(row) for row in csv.DictReader(handle)]


def write_inventory(rows: Sequence[dict[str, Any]], path: Path, dry_run: bool = False) -> None:
    if dry_run:
        LOG.info("dry-run: would write %d row(s) to %s", len(rows), path)
        for row in rows[:10]:
            LOG.debug("dry-run row: %s", row)
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(FIELDS))
        writer.writeheader()
        writer.writerows(rows)
    LOG.info("wrote %d row(s) to %s", len(rows), path)


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate the synthetic P3 account/group inventory for admin tiering.",
    )
    parser.add_argument("--staff-csv", type=Path, default=DEFAULT_STAFF_CSV,
                        help="the P1 synthetic staff file (referenced, never duplicated)")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT,
                        help="where to write the inventory CSV")
    parser.add_argument("--dry-run", action="store_true", help="report without writing")
    parser.add_argument("-v", "--verbose", action="store_true", help="verbose logging")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(message)s",
    )
    try:
        staff = read_staff(args.staff_csv)
    except FileNotFoundError as error:
        LOG.error("%s", error)
        return 2
    inventory = build_inventory(staff)
    write_inventory(inventory, args.output, args.dry_run)
    admins = sum(1 for row in inventory if row["Type"] == "Admin")
    LOG.info("%d staff row(s) -> %d account row(s) (%d admin)", len(staff), len(inventory), admins)
    LOG.warning("SYNTHETIC DATA: fictional people from the P1 synthetic staff file. Label it as synthetic wherever it appears.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
