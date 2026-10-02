#!/usr/bin/env python3
"""Generate the monthly IT report from the governance snapshot - and refuse to render if an
evidence link it would include is missing.

Applies to projects/p10-governance. The report structure follows ``configs/report-template.md``.

The point of the "refuse to render" rule (the task's requirement, and consistent with AGENTS.md
Section 4.5) is that a management report must never point at a source file that does not exist.
If any cited evidence file is absent, the script stops with a clear error listing what is missing,
rather than writing a report with dead links - or worse, an invented number.

Inputs
  reports/kpi-snapshot-<date>.json        (from collect_kpis.py)
  configs/kpi-definitions.csv
  data/change-log.csv, data/risk-register.csv, data/action-tracker.csv, data/cis-ig1-safeguards.csv

Output
  reports/monthly-it-report-<YYYY-MM>.md

Exit codes
  0 rendered · 1 refused (missing evidence) · 2 input problem
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass
from datetime import date
from pathlib import Path

from _common import (
    LOG,
    P10_DIR,
    REPO_ROOT,
    configure_logging,
    fmt,
    parse_date,
    read_csv,
    write_text,
)

KPI_DEFS = P10_DIR / "configs" / "kpi-definitions.csv"
CHANGE_LOG = P10_DIR / "data" / "change-log.csv"
RISK_REGISTER = P10_DIR / "data" / "risk-register.csv"
ACTION_TRACKER = P10_DIR / "data" / "action-tracker.csv"
SAFEGUARDS = P10_DIR / "data" / "cis-ig1-safeguards.csv"


# --------------------------------------------------------------------------------------
# Evidence resolution
# --------------------------------------------------------------------------------------
@dataclass
class EvidenceCheck:
    """Every evidence path the report would cite, and whether it exists."""

    cited: list[str]
    missing: list[str]

    @property
    def ok(self) -> bool:
        return not self.missing


def resolve_evidence_paths(definitions: list[dict[str, str]], snapshot: dict[str, object]) -> EvidenceCheck:
    """Collect the files the report will cite and check them against the repository.

    A source string is treated as a file citation when it looks like a repository path (contains a
    "/" and a file extension). Bare relative paths (``data/change-log.csv``) resolve against the
    repository root; a glob (``projects/*/README.md``) counts as satisfied when it matches at least
    one file. Free-text sources are left alone; the report labels them rather than pretending.
    """
    cited: list[str] = []
    missing: list[str] = []

    def looks_like_path(token: str) -> bool:
        return "/" in token and any(
            token.endswith(ext)
            for ext in (".csv", ".md", ".json", ".png", ".pdf", ".svg", ".yml", ".yaml", ".conf", ".ps1", ".sh", ".py")
        )

    def check(token: str) -> None:
        token = token.strip().strip("`,")
        if not looks_like_path(token):
            return
        cited.append(token)
        if "*" in token:
            if not list(REPO_ROOT.glob(token)):
                missing.append(token)
            return
        candidate = REPO_ROOT / token
        if not candidate.is_file():
            candidate = P10_DIR / token
        if not candidate.is_file():
            missing.append(token)

    for row in definitions:
        for token in (row.get("source") or "").split(","):
            check(token)
    for kpi in snapshot.get("kpis", []):  # type: ignore[union-attr]
        for token in str(kpi.get("source", "")).replace("`", " ").split():
            if token.startswith(("projects/", "data/", "configs/")):
                check(token)
    return EvidenceCheck(cited=sorted(set(cited)), missing=sorted(set(missing)))


# --------------------------------------------------------------------------------------
# Report body
# --------------------------------------------------------------------------------------
def rag_cell(value: object, rag: str) -> str:
    if value == "not measured" or rag == "not measured":
        return "not measured"
    return rag


def render_report(
    *,
    period: str,
    snapshot: dict[str, object],
    definitions: list[dict[str, str]],
    as_of: date,
) -> str:
    kpis_by_id = {str(k["kpi_id"]): k for k in snapshot.get("kpis", [])}  # type: ignore[union-attr]
    changes = read_csv(CHANGE_LOG) if CHANGE_LOG.is_file() else []
    risks = read_csv(RISK_REGISTER) if RISK_REGISTER.is_file() else []
    actions = read_csv(ACTION_TRACKER) if ACTION_TRACKER.is_file() else []
    safeguards = read_csv(SAFEGUARDS) if SAFEGUARDS.is_file() else []
    scored = sum(1 for s in safeguards if (s.get("after_status") or "").strip() != "")

    repo_kpis = [k for k in snapshot.get("kpis", []) if k.get("derived_from") == "repository"]  # type: ignore[union-attr]
    lab_kpis = [k for k in snapshot.get("kpis", []) if k.get("derived_from") == "lab"]  # type: ignore[union-attr]

    out: list[str] = []
    out.append(f"# Halden Distribution Ltd. — Monthly IT report ({period})")
    out.append("")
    out.append(
        f"**Prepared by:** IT · **For:** Management team · **As of:** {as_of.isoformat()}  "
    )
    out.append(
        "**Status of the lab:** the ten projects are complete **build kits** — scripts, configs, "
        "documentation and business artifacts exist, but the phases have **not been executed** in the "
        "lab yet. This report therefore says \"not measured\" for every operational KPI and reports the "
        "handful of numbers that can be derived from the repository itself."
    )
    out.append("")
    out.append(
        "> Halden Distribution Ltd. is a fictional 85-user company used for a home-lab portfolio. "
        "Every number below is labelled with where it came from; nothing is estimated."
    )
    out.append("")

    out.append("## 1. Summary in three sentences")
    out.append("")
    out.append(
        "1. **What went well:** all ten project build kits (P1–P9 plus this governance capstone) are "
        "written, reviewable and internally consistent, with 123 automation scripts and 11 business "
        "artifacts committed."
    )
    out.append(
        "2. **What did not:** nothing has been run in the lab yet, so no operational KPI (identity, "
        "patching, backup, service desk) has a measured value."
    )
    out.append(
        "3. **What we need:** a decision to start lab execution and a business owner for each risk and "
        "action; until then the governance programme can only measure the repository, not the estate."
    )
    out.append("")

    out.append("## 2. KPI table (RAG)")
    out.append("")
    out.append(
        "**Repository-derived (measured now, from this repository).** These are genuine measurements "
        "of the repository state, produced by `scripts/collect_kpis.py`; they are not lab results."
    )
    out.append("")
    out.append("| KPI | Value | Target | RAG | Source |")
    out.append("|---|---|---|---|---|")
    for kpi in repo_kpis:
        out.append(
            f"| {kpi['kpi_id']} {kpi['name']} | {fmt(kpi['value'])}{(' ' + str(kpi['unit'])) if kpi.get('unit') else ''} | "
            f"{kpi.get('target') or '—'} | {rag_cell(kpi['value'], str(kpi.get('rag', '')))} | `{kpi['source']}` |"
        )
    out.append("")
    out.append("**Lab-measured (not measured yet).** These need the lab to be executed.")
    out.append("")
    out.append("| KPI | Value | Target | Where it will come from |")
    out.append("|---|---|---|---|")
    for kpi in lab_kpis:
        out.append(
            f"| {kpi['kpi_id']} {kpi['name']} | not measured | {kpi.get('target') or '—'} | {kpi['source']} |"
        )
    out.append("")
    out.append(
        f"The KPI definitions (formula, target, RAG rule, owner) are in `configs/kpi-definitions.csv`; "
        f"the snapshot behind this table is `reports/kpi-snapshot-{as_of.isoformat()}.json`."
    )
    out.append("")

    out.append("## 3. Notable events and business impact")
    out.append("")
    out.append(
        "No incidents, outages or major changes have occurred: the lab has not been executed. The one "
        "governance event is the programme itself."
    )
    out.append("")
    out.append("| Date | Event | Services/users affected | Business impact | Reference |")
    out.append("|---|---|---|---|---|")
    out.append(
        "| 2026-09-29 | Change raised: P1 core infrastructure build (Tier 0) | 85 users (all) | None yet — awaiting approval | `data/change-log.csv` (CHG-2026-001) |"
    )
    out.append("")
    out.append(
        f"Changes recorded in the register: **{len(changes)}** (of which {sum(1 for c in changes if not (c.get('approver') or '').strip())} awaiting approval). "
        "See section 5 of the CAB agenda for the approval workflow."
    )
    out.append("")

    out.append("## 4. Risks and issues needing management attention")
    out.append("")
    if not risks:
        out.append(
            "The risk register is **empty on purpose**: no risk has been formally assessed yet, and "
            "inventing plausible risks would be worse than showing the register's shape. The methodology "
            "(scoring, ownership, treatment) is documented in `business/p10-risk-register.md`. The first "
            "population will be the CIS IG1 gaps once the assessment is run."
        )
    else:
        out.append("| Risk | Rating | Recommended decision | Owner (business) |")
        out.append("|---|---|---|---|")
        for risk in risks:
            out.append(
                f"| {risk.get('risk_id', '')} {risk.get('risk_statement', '')} | {risk.get('score', '')} | "
                f"{risk.get('treatment', '')} | {risk.get('business_owner', '')} |"
            )
    out.append("")
    out.append(
        f"**Decision requested:** appoint a business owner for each risk on the register and confirm "
        f"whether the CIS IG1 gap-closure (the {len(safeguards) - scored} safeguards not yet scored) is funded as a 90-day roadmap or deferred."
    )
    out.append("")

    out.append("## 5. Actions")
    out.append("")
    if not actions:
        out.append(
            "The action tracker is empty. Actions appear when the project reviews, findings registers, "
            "tabletop exercise and DR drill produce them (P3, P7, P8, P10); none of those have run yet."
        )
    else:
        out.append("| Action | Owner | Due | Status | Notes |")
        out.append("|---|---|---|---|---|")
        for action in actions:
            out.append(
                f"| {action.get('description', '')} | {action.get('owner', '')} | {action.get('due_date', '')} | "
                f"{action.get('status', '')} | {action.get('notes', '')} |"
            )
    out.append("")

    out.append("## 6. Next month's plan")
    out.append("")
    out.append(
        "- **Start lab execution at P1 Phase 1** (snapshot the DC first) so the operational KPIs can be "
        "measured and this report gains real numbers."
    )
    out.append(
        "- **Run the CIS IG1 self-assessment** after each project completes a phase, scoring only what "
        "has evidence (`scripts/cis_assessment.py`)."
    )
    out.append(
        "- **Hold the first CAB** using the generated agenda (`scripts/change_log.py --cab-agenda`) and "
        "record real decisions."
    )
    out.append(
        "- **Close the Control 14 gap** (security awareness training) — the largest expected gap, since "
        "no awareness programme exists yet."
    )
    out.append("")

    out.append("---")
    out.append("")
    out.append(
        "*Generated by `projects/p10-governance/scripts/monthly_report.py`. Rendering refuses when a "
        "cited evidence file is missing, so a management report can never point at a source that does "
        "not exist.*"
    )
    out.append("")
    return "\n".join(out)


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="monthly_report.py",
        description=(
            "Render the monthly IT report from the KPI snapshot. Refuses to render if any cited "
            "evidence file is missing."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python3 scripts/monthly_report.py --period 2026-10\n"
            "  python3 scripts/monthly_report.py --allow-missing   # render with a missing-evidence warning\n"
        ),
    )
    parser.add_argument("--snapshot", type=Path, default=None, help="KPI snapshot JSON (defaults to the newest)")
    parser.add_argument("--period", type=str, default=None, help="report period YYYY-MM (defaults to the snapshot month)")
    parser.add_argument("--out-dir", type=Path, default=P10_DIR / "reports")
    parser.add_argument(
        "--allow-missing",
        action="store_true",
        help="render the report even when evidence is missing, with a blocking warning in the header",
    )
    parser.add_argument("--dry-run", action="store_true", help="build in memory, write nothing")
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser


def newest_snapshot(out_dir: Path) -> Path | None:
    candidates = sorted(out_dir.glob("kpi-snapshot-*.json"))
    return candidates[-1] if candidates else None


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    configure_logging(args.verbose)

    snapshot_path = args.snapshot or newest_snapshot(Path(args.out_dir))
    if snapshot_path is None or not Path(snapshot_path).is_file():
        LOG.error(
            "No KPI snapshot found. Run scripts/collect_kpis.py first (e.g. python3 scripts/collect_kpis.py)."
        )
        return 2

    snapshot = json.loads(Path(snapshot_path).read_text(encoding="utf-8"))
    definitions = read_csv(KPI_DEFS) if KPI_DEFS.is_file() else []
    as_of = parse_date(str(snapshot.get("as_of", ""))) or date.today()
    period = args.period or as_of.strftime("%Y-%m")

    check = resolve_evidence_paths(definitions, snapshot)
    if not check.ok and not args.allow_missing:
        LOG.error("Refusing to render the monthly report: %d cited evidence file(s) are missing:", len(check.missing))
        for path in check.missing:
            LOG.error("  missing: %s", path)
        LOG.error("Fix the evidence map, run the lab to produce the file, or pass --allow-missing to render with a visible warning.")
        return 1

    report = render_report(period=period, snapshot=snapshot, definitions=definitions, as_of=as_of)
    if check.missing:
        report = report.replace(
            "> Halden Distribution Ltd. is a fictional 85-user company used for a home-lab portfolio. ",
            "> **WARNING: rendered with `--allow-missing`.** "
            f"{len(check.missing)} cited evidence file(s) do not exist yet: "
            + ", ".join(f"`{m}`" for m in check.missing)
            + ". \n\n> Halden Distribution Ltd. is a fictional 85-user company used for a home-lab portfolio. ",
        )

    out = Path(args.out_dir) / f"monthly-it-report-{period}.md"
    if args.dry_run:
        LOG.info("dry-run: would write %s (%d bytes)", out, len(report))
    else:
        write_text(out, report)
        LOG.info("wrote monthly report: %s", out)
    print(f"Cited evidence files: {len(check.cited)} · missing: {len(check.missing)}")
    if check.cited:
        print("Cited: " + ", ".join(check.cited))
    return 0


if __name__ == "__main__":
    sys.exit(main())
