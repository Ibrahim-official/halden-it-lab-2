#!/usr/bin/env python3
"""Validate the change register and build the CAB agenda.

Applies to projects/p10-governance. Implements the change-management procedure in
``configs/change-policy-fields.yaml`` and ``configs/change-type-matrix.csv`` against the register
``data/change-log.csv``.

What it does
  1. Validates every change record: required fields present, change_type and risk inside the
     allowed values, status inside the allowed values, rollback plan present (a change with no
     rollback note is not approvable), and emergency changes carry a retrospective.
  2. Builds a CAB agenda for the next meeting, ordered the way the procedure says.
  3. Prints change KPIs (by type, unsigned approvals, emergency share, oldest open change) - these
     are repository-derived counts, not lab measurements.

Exit codes
  0 clean · 1 validation errors · 2 input problem

Examples
  python3 scripts/change_log.py --validate --open-errors
  python3 scripts/change_log.py --cab-agenda --out reports/cab-agenda-2026-10-02.md
"""

from __future__ import annotations

import argparse
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path

from _common import (
    LOG,
    P10_DIR,
    age_days,
    configure_logging,
    frontmatter_scalar,
    parse_date,
    read_csv,
    write_text,
)

CHANGE_LOG = P10_DIR / "data" / "change-log.csv"
POLICY_FIELDS = P10_DIR / "configs" / "change-policy-fields.yaml"
TYPE_MATRIX = P10_DIR / "configs" / "change-type-matrix.csv"

VALID_TYPES = {"standard", "normal", "emergency"}
VALID_RISKS = {"low", "medium", "high"}
VALID_STATUS = {"planned", "pending", "approved", "implemented", "reviewed", "rejected", "withdrawn"}

# Every normal/emergency change must carry these values before approval.
REQUIRED_FIELDS = [
    "change_id",
    "date_raised",
    "title",
    "change_type",
    "risk",
    "requested_by",
    "status",
    "category",
    "affected_services",
    "test_plan",
    "rollback_plan",
]


@dataclass
class Change:
    """One change record from the register."""

    row: dict[str, str]

    @property
    def change_id(self) -> str:
        return self.row.get("change_id", "")

    @property
    def change_type(self) -> str:
        return (self.row.get("change_type") or "").strip().lower()

    @property
    def risk(self) -> str:
        return (self.row.get("risk") or "").strip().lower()

    @property
    def status(self) -> str:
        return (self.row.get("status") or "").strip().lower()

    @property
    def date_raised(self) -> date | None:
        return parse_date(self.row.get("date_raised", ""))

    @property
    def approver(self) -> str:
        return (self.row.get("approver") or "").strip()

    @property
    def is_unsigned(self) -> bool:
        return not self.approver and not (self.row.get("approval_date") or "").strip()

    def age_days(self, *, today: date | None = None) -> int | None:
        return age_days(self.date_raised, today=today)


@dataclass
class Register:
    """The validated register."""

    changes: list[Change]
    errors: list[str]
    warnings: list[str]

    @property
    def not_yet_approved(self) -> list[Change]:
        return [c for c in self.changes if c.is_unsigned and c.status in {"planned", "pending"}]

    def by_type(self) -> dict[str, list[Change]]:
        result: dict[str, list[Change]] = {}
        for change in self.changes:
            result.setdefault(change.change_type or "untyped", []).append(change)
        return result

    def kpi_counts(self, *, today: date | None = None) -> dict[str, object]:
        total = len(self.changes)
        emergency = len(self.by_type().get("emergency", []))
        unsigned = sum(1 for c in self.changes if c.is_unsigned)
        ages = [c.age_days(today=today) for c in self.changes if c.age_days(today=today) is not None]
        return {
            "total_changes": total,
            "by_type": {k: len(v) for k, v in self.by_type().items()},
            "emergency_share_percent": (100.0 * emergency / total) if total else None,
            "unsigned_approvals": unsigned,
            "oldest_open_change_days": max(ages) if ages else None,
        }


# --------------------------------------------------------------------------------------
# Validation
# --------------------------------------------------------------------------------------
def validate(register: Register, *, today: date | None = None) -> None:
    """Fill the register's errors and warnings in place."""
    seen: set[str] = set()
    for index, change in enumerate(register.changes, start=2):
        cid = change.change_id or f"row {index}"
        ctx = f"{CHANGE_LOG.name}:{index} change {cid}"

        if not change.change_id:
            register.errors.append(f"{ctx}: change_id is missing")
        elif change.change_id in seen:
            register.errors.append(f"{ctx}: duplicate change_id")
        seen.add(change.change_id)

        for field in REQUIRED_FIELDS:
            if not (change.row.get(field) or "").strip():
                register.errors.append(f"{ctx}: required field '{field}' is empty")

        if change.change_type and change.change_type not in VALID_TYPES:
            register.errors.append(
                f"{ctx}: change_type {change.change_type!r} is not one of {sorted(VALID_TYPES)}"
            )
        if change.risk and change.risk not in VALID_RISKS:
            register.errors.append(f"{ctx}: risk {change.risk!r} is not one of {sorted(VALID_RISKS)}")
        if change.status and change.status not in VALID_STATUS:
            register.errors.append(f"{ctx}: status {change.status!r} is not one of {sorted(VALID_STATUS)}")

        # The rollback rule: a change without a rollback note is not approvable.
        if not (change.row.get("rollback_plan") or "").strip():
            register.errors.append(f"{ctx}: no rollback plan - this change cannot be approved")

        # Status gates from the policy file.
        if change.status in {"approved", "implemented", "reviewed"} and change.is_unsigned:
            register.errors.append(f"{ctx}: status is {change.status} but there is no named approver")
        if change.status == "reviewed" and not (change.row.get("post_implementation_review") or "").strip():
            register.errors.append(f"{ctx}: status is reviewed but the post-implementation review is empty")

        # Emergency changes must be reviewed retrospectively.
        if change.change_type == "emergency" and change.status in {"implemented", "reviewed"}:
            if not (change.row.get("post_implementation_review") or "").strip():
                register.errors.append(
                    f"{ctx}: emergency change is implemented but has no retrospective review"
                )
            else:
                register.warnings.append(f"{ctx}: emergency change - confirm the retrospective review is within 2 business days")

        # Soft checks.
        if change.change_type == "normal" and change.risk == "low":
            register.warnings.append(f"{ctx}: a low-risk normal change may belong in the standard catalogue")
        if change.date_raised is None:
            register.warnings.append(f"{ctx}: date_raised is not a valid ISO date")
        elif change.age_days(today=today) is not None and change.age_days(today=today) > 30 and change.is_unsigned:
            register.warnings.append(
                f"{ctx}: raised {change.age_days(today=today)} days ago and still unsigned"
            )

    # The type matrix must define every type the register uses.
    if TYPE_MATRIX.is_file():
        defined = {(r.get("change_type") or "").strip().lower() for r in read_csv(TYPE_MATRIX)}
        for change_type in sorted({c.change_type for c in register.changes if c.change_type}):
            if change_type not in defined:
                register.errors.append(
                    f"change_type {change_type!r} is used in {CHANGE_LOG.name} but is not defined in {TYPE_MATRIX.name}"
                )


def load_register(path: Path = CHANGE_LOG) -> Register:
    if not path.is_file():
        raise FileNotFoundError(f"Change log not found: {path}")
    changes = [Change(row) for row in read_csv(path)]
    register = Register(changes=changes, errors=[], warnings=[])
    validate(register)
    return register


# --------------------------------------------------------------------------------------
# CAB agenda
# --------------------------------------------------------------------------------------
def render_agenda(register: Register, *, as_of: date, chair: str = "IT Lead") -> str:
    """Render the CAB agenda in the order the procedure specifies."""
    out: list[str] = []
    counts = register.kpi_counts(today=as_of)
    out.append(f"# Halden Distribution Ltd. — Change Advisory Board agenda ({as_of.isoformat()})")
    out.append("")
    out.append(
        "> **Template with nothing approved yet.** Halden Distribution Ltd. is a fictional company. "
        "Every decision line below is marked *pending* until a real review happens in the lab; the "
        "script never writes an approval on the owner's behalf."
    )
    out.append("")
    out.append(f"**Chair:** {chair}  ·  **Duration:** 15 minutes  ·  **Minute taker:** Service Desk  ")
    out.append(
        f"**Register as read:** {counts['total_changes']} change(s), {counts['unsigned_approvals']} awaiting approval  "
    )
    out.append("")
    out.append("## Standing attendees")
    out.append("")
    out.append("- IT Lead (chair) · Service Desk representative · affected department head")
    out.append("- Management attends when the change is high risk or touches a Tier 0 service")
    out.append("")

    out.append("## 1. Emergency retrospectives (5 min)")
    out.append("")
    emergencies = [
        c for c in register.changes
        if c.change_type == "emergency" and c.status in {"implemented", "reviewed"}
    ]
    if not emergencies:
        out.append("No emergency changes to review. *(A retro must be held within 2 business days of any emergency change.)*")
    else:
        out.append("| Change | Title | Implemented | Retrospective review | Decision |")
        out.append("|---|---|---|---|---|")
        for c in emergencies:
            out.append(
                f"| {c.change_id} | {c.row.get('title', '')} | {c.row.get('approval_date') or 'not recorded'} | "
                f"{c.row.get('post_implementation_review') or 'missing'} | pending |"
            )
    out.append("")

    out.append("## 2. Changes awaiting approval (5 min)")
    out.append("")
    pending = register.not_yet_approved
    if not pending:
        out.append("No changes are awaiting approval.")
    else:
        out.append("| Change | Type | Risk | Title | Rollback plan? | Recommend |")
        out.append("|---|---|---|---|---|---|")
        for c in pending:
            has_rollback = bool((c.row.get("rollback_plan") or "").strip())
            recommendation = "approve" if has_rollback else "cannot approve (no rollback plan)"
            out.append(
                f"| {c.change_id} | {c.change_type or '?'} | {c.risk or '?'} | {c.row.get('title', '')} | "
                f"{'yes' if has_rollback else 'no'} | {recommendation} |"
            )
    out.append("")

    out.append("## 3. Changes implemented since the last CAB (2 min)")
    out.append("")
    implemented = [c for c in register.changes if c.status in {"implemented", "reviewed"}]
    if not implemented:
        out.append("None recorded.")
    else:
        out.append("| Change | Title | Implemented | Outcome |")
        out.append("|---|---|---|---|")
        for c in implemented:
            out.append(
                f"| {c.change_id} | {c.row.get('title', '')} | {c.row.get('approval_date') or 'not recorded'} | "
                f"{c.row.get('post_implementation_review') or 'review pending'} |"
            )
    out.append("")

    out.append("## 4. Post-implementation reviews due (1 min)")
    out.append("")
    due = [
        c for c in register.changes
        if c.status == "implemented" and not (c.row.get("post_implementation_review") or "").strip()
    ]
    out.append(
        "\n".join(f"- {c.change_id} — {c.row.get('title', '')}" for c in due)
        if due else "None outstanding."
    )
    out.append("")

    out.append("## 5. Risks and unauthorised changes (1 min)")
    out.append("")
    out.append("- Unauthorised changes detected since the last CAB: **not measured** (depends on the P9 config drift report).")
    out.append("- Risks needing a CAB decision: see `business/p10-risk-register.md` (register empty until real risks are assessed).")
    out.append("")

    out.append("## 6. Actions (1 min)")
    out.append("")
    out.append("Review `data/action-tracker.csv`; carried-over actions keep their owner and due date.")
    out.append("")

    out.append("## Decisions")
    out.append("")
    out.append("| Change | Decision (approve / defer / reject) | Decided by | Date | Notes |")
    out.append("|---|---|---|---|---|")
    for c in register.changes:
        out.append(f"| {c.change_id} | pending |  |  |  |")
    out.append("")
    out.append("---")
    out.append("")
    out.append(
        "*Generated by `projects/p10-governance/scripts/change_log.py`. The decisions table is "
        "deliberately empty: no approval is recorded until a CAB actually meets.*"
    )
    out.append("")
    return "\n".join(out)


def console_summary(register: Register, *, today: date) -> str:
    counts = register.kpi_counts(today=today)
    lines = [
        f"Changes: {counts['total_changes']} · by type: {counts['by_type']}",
        f"Unsigned/awaiting approval: {counts['unsigned_approvals']}",
        f"Emergency share: {counts['emergency_share_percent'] if counts['emergency_share_percent'] is not None else 'n/a'}%",
        f"Oldest open change: {counts['oldest_open_change_days']} day(s)",
        f"Validation: {len(register.errors)} error(s), {len(register.warnings)} warning(s)",
    ]
    return "\n".join(lines)


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="change_log.py",
        description=(
            "Validate the Halden change register and build the CAB agenda. Approvals are never "
            "written automatically; the decisions table stays pending."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python3 scripts/change_log.py --validate\n"
            "  python3 scripts/change_log.py --cab-agenda --out reports/cab-agenda.md\n"
        ),
    )
    parser.add_argument("--log", type=Path, default=CHANGE_LOG, help="change register CSV")
    parser.add_argument("--validate", action="store_true", help="validate the register and print the KPIs")
    parser.add_argument("--cab-agenda", action="store_true", help="write the CAB agenda")
    parser.add_argument("--out", type=Path, default=None, help="agenda output path (Markdown)")
    parser.add_argument("--chair", type=str, default="IT Lead", help="CAB chair (agenda header)")
    parser.add_argument("--as-of", type=str, default=None, help="date to treat as today (YYYY-MM-DD)")
    parser.add_argument("--open-errors", action="store_true", help="exit 1 when validation errors are found")
    parser.add_argument("--dry-run", action="store_true", help="validate and print, write nothing")
    parser.add_argument("-v", "--verbose", action="store_true", help="verbose logging")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    configure_logging(args.verbose)
    as_of = parse_date(args.as_of) or date.today()

    try:
        register = load_register(args.log)
    except FileNotFoundError as exc:
        LOG.error("%s", exc)
        return 2

    print(console_summary(register, today=as_of))
    for error in register.errors:
        LOG.error("%s", error)
    for warning in register.warnings:
        LOG.warning("%s", warning)

    if args.cab_agenda:
        agenda = render_agenda(register, as_of=as_of, chair=args.chair)
        out = args.out or (P10_DIR / "reports" / f"cab-agenda-{as_of.isoformat()}.md")
        if args.dry_run:
            LOG.info("dry-run: would write %s", out)
        else:
            write_text(Path(out), agenda)
            LOG.info("wrote CAB agenda: %s", out)

    if args.open_errors and register.errors:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
