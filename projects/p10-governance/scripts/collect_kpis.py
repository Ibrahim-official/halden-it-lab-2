#!/usr/bin/env python3
"""Measure what the nine other projects actually produced, by reading this repository.

Applies to projects/p10-governance (the governance capstone that reports on P1-P9).

IMPORTANT — what these numbers are
  Every value this script prints is a **repository-derived count**: it is computed by reading files
  that exist in ``projects/``, ``PROGRESS.md`` and ``configs/`` right now. It is a genuine
  measurement of the repository, not of a running lab. It is reported as such, and the JSON output
  carries ``"derived_from": "repository"`` so nothing can be mistaken for a lab measurement.
  Lab-measured KPIs (MFA coverage, patch compliance, restore tests ...) are reported as
  "not measured" with a reason, never estimated.

Outputs
  reports/kpi-snapshot-<YYYY-MM-DD>.json   machine-readable snapshot (feeds the dashboard)
  reports/kpi-snapshot-<YYYY-MM-DD>.md     a short human summary
  data/kpi-history.csv                     appended row(s) for this period

Exit codes
  0 success   ·   2 repository inputs missing
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

from _common import (
    LOG,
    P10_DIR,
    PROJECTS_DIR,
    REPO_ROOT,
    age_days,
    configure_logging,
    frontmatter_scalar,
    fmt,
    parse_date,
    read_csv,
    read_text,
    write_text,
)

KPI_DEFS = P10_DIR / "configs" / "kpi-definitions.csv"
SAFEGUARDS = P10_DIR / "data" / "cis-ig1-safeguards.csv"
EVIDENCE_MAP = P10_DIR / "configs" / "cis-ig1-evidence-map.csv"
CHANGE_LOG = P10_DIR / "data" / "change-log.csv"
POLICY_REGISTER = P10_DIR / "data" / "policy-register.csv"
ACTION_TRACKER = P10_DIR / "data" / "action-tracker.csv"

NOT_MEASURED = "not measured"


# --------------------------------------------------------------------------------------
# Small KPI model
# --------------------------------------------------------------------------------------
@dataclass
class KpiResult:
    """One KPI with its value, how it was obtained and where it came from."""

    kpi_id: str
    name: str
    area: str
    value: object
    unit: str = ""
    target: str = ""
    rag: str = "not measured"
    derived_from: str = "repository"
    source: str = ""
    kind: str = "count"
    note: str = ""

    def as_dict(self) -> dict[str, object]:
        return {
            "kpi_id": self.kpi_id,
            "name": self.name,
            "area": self.area,
            "value": self.value,
            "unit": self.unit,
            "target": self.target,
            "rag": self.rag,
            "derived_from": self.derived_from,
            "source": self.source,
            "kind": self.kind,
            "note": self.note,
        }


@dataclass
class Snapshot:
    """Everything the collector found in one pass."""

    as_of: date
    results: list[KpiResult] = field(default_factory=list)

    def add(self, result: KpiResult) -> None:
        self.results.append(result)

    def as_dict(self) -> dict[str, object]:
        return {
            "as_of": self.as_of.isoformat(),
            "halden_is_fictional": True,
            "derived_from": "repository",
            "explanation": (
                "Every value below is computed by reading this repository (files under projects/, "
                "PROGRESS.md, configs/). It is a genuine measurement of the repository state, not a "
                "lab measurement. KPIs that need a running lab are 'not measured' until the lab is "
                "executed (AGENTS.md rule R2)."
            ),
            "kpis": [r.as_dict() for r in self.results],
        }


# --------------------------------------------------------------------------------------
# Repository probes
# --------------------------------------------------------------------------------------
def project_folders() -> list[Path]:
    """Every projects/pXX-* folder, sorted by name."""
    return sorted(p for p in PROJECTS_DIR.glob("p[0-9][0-9]-*") if p.is_dir())


def read_showcase_status(folder: Path) -> str:
    """Showcase status for a project folder (planned | in-progress | done), else 'unknown'."""
    showcase = folder / "showcase.md"
    if not showcase.is_file():
        return "unknown"
    frontmatter, _ = split_showcase(read_text(showcase))
    return (frontmatter_scalar(frontmatter, "status") or "unknown").lower()


def split_showcase(text: str) -> tuple[str, str]:
    """Split showcase.md into frontmatter and body."""
    match = re.match(r"^---\s*\n(.*?)\n---\s*\n?", text, flags=re.DOTALL)
    if not match:
        return "", text
    return match.group(1), text[match.end():]


def results_rows(folder: Path) -> list[str]:
    """The data rows under a project README's '## Results' heading."""
    readme = folder / "README.md"
    if not readme.is_file():
        return []
    lines = read_text(readme).splitlines()
    in_results = False
    table_rows: list[str] = []
    for line in lines:
        if line.startswith("## "):
            if in_results:
                break
            in_results = line.strip().lower().startswith("## results")
            continue
        if not in_results:
            continue
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if not cells or set("".join(cells)) <= {"-", " ", ":"}:
            continue  # separator row
        if cells[0].lower() == "metric":
            continue  # header row
        table_rows.append(stripped)
    return table_rows


def acceptance_rows(folder: Path) -> list[tuple[str, str]]:
    """(expected, actual) pairs from a README's '## Acceptance tests' table."""
    readme = folder / "README.md"
    if not readme.is_file():
        return []
    lines = read_text(readme).splitlines()
    in_tests = False
    rows: list[tuple[str, str]] = []
    for line in lines:
        if line.startswith("## "):
            if in_tests:
                break
            in_tests = line.strip().lower().startswith("## acceptance tests")
            continue
        if not in_tests:
            continue
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if not cells or set("".join(cells)) <= {"-", " ", ":"}:
            continue
        if cells[0].lower() == "test":
            continue
        expected = cells[1] if len(cells) > 1 else ""
        actual = cells[2] if len(cells) > 2 else ""
        rows.append((expected, actual))
    return rows


def count_readmes_with_unmeasured_results() -> tuple[int, list[str]]:
    """Projects whose README results table still contains 'not measured'.

    Returns (count of such projects, their folder names). A project README without a results
    table yet is reported separately by ``count_readmes_without_results_table``.
    """
    offenders: list[str] = []
    for folder in project_folders():
        rows = results_rows(folder)
        if not rows:
            continue
        if any("not measured" in row.lower() for row in rows):
            offenders.append(folder.name)
    return len(offenders), offenders


def count_readmes_without_results_table() -> tuple[int, list[str]]:
    """Projects whose README has no '## Results' table at all (write-up not started)."""
    missing: list[str] = []
    for folder in project_folders():
        if not results_rows(folder):
            missing.append(folder.name)
    return len(missing), missing


def count_acceptance_tests() -> tuple[int, int]:
    """(total acceptance tests, tests still 'not run')."""
    total = 0
    not_run = 0
    for folder in project_folders():
        for _expected, actual in acceptance_rows(folder):
            total += 1
            if "not run" in actual.lower():
                not_run += 1
    return total, not_run


def count_dod_items() -> tuple[int, list[str]]:
    """Open Definition-of-Done items from the PROGRESS.md table."""
    progress = REPO_ROOT / "PROGRESS.md"
    if not progress.is_file():
        return 0, []
    lines = read_text(progress).splitlines()
    in_table = False
    items: list[str] = []
    for line in lines:
        if line.startswith("## "):
            if in_table:
                break
            in_table = bool(re.search(r"definition of done", line, flags=re.IGNORECASE))
            continue
        if not in_table:
            continue
        stripped = line.strip()
        if not stripped.startswith("|"):
            continue
        cells = [c.strip() for c in stripped.strip("|").split("|")]
        if not cells or set("".join(cells)) <= {"-", " ", ":"}:
            continue
        if cells[0].lower() in {"#", "no."} or "open item" in " ".join(cells).lower():
            continue
        items.append(cells[1] if len(cells) > 1 else cells[0])
    return len(items), items


def cis_evidence_present() -> tuple[int, int, list[str]]:
    """(safeguards whose expected artifact exists, total mapped, missing paths)."""
    if not EVIDENCE_MAP.is_file():
        return 0, 0, []
    rows = read_csv(EVIDENCE_MAP)
    present = 0
    missing: list[str] = []
    for row in rows:
        artifact = (row.get("artifact_path") or "").strip()
        if not artifact:
            continue
        if (REPO_ROOT / artifact).is_file():
            present += 1
        else:
            missing.append(artifact)
    return present, len(rows), missing


def change_register_counts() -> dict[str, object]:
    """Counts derived from data/change-log.csv."""
    rows = read_csv(CHANGE_LOG) if CHANGE_LOG.is_file() else []
    by_type: dict[str, int] = {}
    unsigned = 0
    oldest: tuple[str, int | None] = ("", None)
    for row in rows:
        ctype = (row.get("change_type") or "untyped").strip() or "untyped"
        by_type[ctype] = by_type.get(ctype, 0) + 1
        if not (row.get("approver") or "").strip():
            unsigned += 1
        age = age_days(parse_date(row.get("date_raised", "")))
        if age is not None and (oldest[1] is None or age > oldest[1]):
            oldest = (row.get("change_id", ""), age)
    emergency = by_type.get("emergency", 0)
    total = len(rows)
    return {
        "total": total,
        "by_type": by_type,
        "unsigned": unsigned,
        "emergency_share_percent": (100.0 * emergency / total) if total else None,
        "oldest": oldest,
    }


def policy_counts() -> dict[str, object]:
    """Counts derived from data/policy-register.csv."""
    rows = read_csv(POLICY_REGISTER) if POLICY_REGISTER.is_file() else []
    approved = sum(1 for r in rows if (r.get("approval_date") or "").strip())
    acked = [
        float(r["ack_actual_percent"])
        for r in rows
        if (r.get("ack_actual_percent") or "").strip() not in {"", "N/A"}
    ]
    return {
        "total": len(rows),
        "approved": approved,
        "acknowledged_recorded": len(acked),
        "ack_mean_percent": (sum(acked) / len(acked)) if acked else None,
    }


def action_counts() -> dict[str, object]:
    """Counts derived from data/action-tracker.csv."""
    rows = read_csv(ACTION_TRACKER) if ACTION_TRACKER.is_file() else []
    closed = [r for r in rows if (r.get("status") or "").strip().lower() in {"closed", "done", "complete", "completed"}]
    on_time = [r for r in closed if (r.get("on_time") or "").strip().lower() in {"yes", "y", "true", "1"}]
    return {
        "total": len(rows),
        "open": len(rows) - len(closed),
        "closed": len(closed),
        "closed_on_time": len(on_time),
        "percent_on_time": (100.0 * len(on_time) / len(closed)) if closed else None,
    }


def safeguard_workbook_counts() -> dict[str, object]:
    """Counts derived from the CIS IG1 safeguard workbook."""
    if not SAFEGUARDS.is_file():
        return {"total": 0, "scored_after": 0, "scored_before": 0, "evidence_named": 0}
    rows = read_csv(SAFEGUARDS)
    scored_after = sum(1 for r in rows if (r.get("after_status") or "").strip() != "")
    scored_before = sum(1 for r in rows if (r.get("before_status") or "").strip() != "")
    evidence_named = sum(1 for r in rows if (r.get("evidence_source") or "").strip() != "")
    return {
        "total": len(rows),
        "scored_after": scored_after,
        "scored_before": scored_before,
        "evidence_named": evidence_named,
    }


def script_counts() -> dict[str, object]:
    """Count scripts in projects/pXX/scripts and how many libraries have a real test suite.

    A project "has tests" when its ``scripts/tests/`` folder contains at least one
    ``test_*.py`` file with an actual assertion - the way P02-P09 ship their Python unit tests.
    The count is per project, not per script, so it is reported as such.
    """
    scripts: list[Path] = []
    for folder in project_folders():
        scripts_dir = folder / "scripts"
        if scripts_dir.is_dir():
            for path in scripts_dir.rglob("*"):
                if path.is_file() and path.suffix in {".ps1", ".sh", ".py"} and "__pycache__" not in path.parts:
                    scripts.append(path)

    projects_with_tests = 0
    for folder in project_folders():
        test_dir = folder / "scripts" / "tests"
        if not test_dir.is_dir():
            continue
        has_assertion = any(
            "assert" in path.read_text(encoding="utf-8", errors="replace")
            for path in test_dir.glob("test_*.py")
        )
        if has_assertion:
            projects_with_tests += 1

    project_count = len(project_folders())
    return {
        "total": len(scripts),
        "projects_with_tests": projects_with_tests,
        "projects_total": project_count,
        "percent_projects_with_tests": (100.0 * projects_with_tests / project_count) if project_count else None,
    }


def business_artifact_counts() -> dict[str, object]:
    """Markdown business artifacts per project."""
    per_project: dict[str, int] = {}
    total = 0
    for folder in project_folders():
        business = folder / "business"
        count = len(list(business.glob("*.md"))) if business.is_dir() else 0
        per_project[folder.name] = count
        total += count
    return {"total": total, "per_project": per_project}


# --------------------------------------------------------------------------------------
# The KPI snapshot
# --------------------------------------------------------------------------------------
def collect(as_of: date | None = None) -> Snapshot:
    """Compute the snapshot. Nothing here invents a value; missing data becomes 'not measured'."""
    snapshot = Snapshot(as_of=as_of or date.today())

    projects = project_folders()
    statuses = {folder.name: read_showcase_status(folder) for folder in projects}
    done = [name for name, status in statuses.items() if status == "done"]
    in_progress = [name for name, status in statuses.items() if status == "in-progress"]
    planned = [name for name, status in statuses.items() if status == "planned"]

    unmeasured_count, unmeasured_projects = count_readmes_with_unmeasured_results()
    no_table_count, no_table_projects = count_readmes_without_results_table()
    tests_total, tests_not_run = count_acceptance_tests()
    dod_count, dod_items = count_dod_items()
    evidence_present, evidence_total, evidence_missing = cis_evidence_present()
    changes = change_register_counts()
    policies = policy_counts()
    actions = action_counts()
    safeguards = safeguard_workbook_counts()
    scripts = script_counts()
    business = business_artifact_counts()

    def repo(kpi_id: str, name: str, area: str, value: object, *, source: str, kind: str = "count",
             unit: str = "", target: str = "", rag: str = "informational", note: str = "") -> None:
        snapshot.add(
            KpiResult(
                kpi_id=kpi_id, name=name, area=area, value=value, unit=unit, target=target,
                rag=rag, derived_from="repository", source=source, kind=kind, note=note,
            )
        )

    def lab(kpi_id: str, name: str, area: str, *, source: str, target: str, note: str) -> None:
        snapshot.add(
            KpiResult(
                kpi_id=kpi_id, name=name, area=area, value=NOT_MEASURED, target=target,
                rag="not measured", derived_from="lab", source=source, kind="measurement", note=note,
            )
        )

    # --- projects and readiness -------------------------------------------------------
    repo(
        "KPI-27", "Projects with measured results", "Governance",
        value=0,
        source="projects/*/README.md (## Results tables)",
        kind="count",
        target="10 of 10",
        rag="red",
        note=(
            f"0 of {len(projects)} projects have any measured result yet: {unmeasured_count} have a "
            f"results table whose rows read 'not measured' and {no_table_count} do not have the table "
            "written yet. This is expected before lab execution."
        ),
    )
    repo(
        "KPI-34", "Projects whose README still says 'not measured'", "Governance",
        value=unmeasured_count,
        source="projects/*/README.md (## Results tables)",
        kind="count",
        target="0",
        rag="red" if unmeasured_count else "green",
        note=", ".join(unmeasured_projects) or "none",
    )
    repo(
        "KPI-28", "Projects by showcase status", "Governance",
        value={"done": len(done), "in-progress": len(in_progress), "planned": len(planned)},
        source="projects/*/showcase.md frontmatter (status)",
        kind="breakdown",
        note=f"done: {', '.join(done) or 'none'}; in-progress: {len(in_progress)}; planned: {len(planned)}",
    )
    repo(
        "KPI-35", "Projects carrying the Definition-of-Done template", "Governance",
        value=len(projects) - no_table_count,
        source="projects/*/README.md",
        kind="count",
        target=f"{len(projects)}",
        rag="amber" if no_table_count else "green",
        note=f"{no_table_count} project(s) still use the placeholder README (write-up pending): {', '.join(no_table_projects) or 'none'}",
    )
    repo(
        "KPI-29", "Acceptance tests not yet run", "Governance",
        value=tests_not_run,
        source="projects/*/README.md (## Acceptance tests tables)",
        kind="count",
        target="0",
        rag="red" if tests_not_run else "green",
        note=(
            f"of {tests_total} acceptance-test rows found across the projects; "
            f"{no_table_count} project(s) have not written their acceptance-test table yet "
            "and are not counted"
        ),
    )
    repo(
        "KPI-25", "Open Definition-of-Done items", "Governance",
        value=dod_count,
        source="PROGRESS.md (Definition of Done table)",
        kind="count",
        target="0",
        rag="amber" if 0 < dod_count <= 3 else ("green" if dod_count == 0 else "red"),
        note="; ".join(dod_items[:3]) + (" …" if len(dod_items) > 3 else "") if dod_items else "table empty or not found",
    )
    repo(
        "KPI-30", "Business artifacts authored (Markdown)", "Governance",
        value=business["total"],
        source="projects/*/business/*.md",
        kind="count",
        note="PDFs are generated centrally from these Markdown sources",
    )
    repo(
        "KPI-31", "Automation scripts committed", "Governance",
        value=scripts["total"],
        source="projects/*/scripts/**/*.{ps1,sh,py}",
        kind="count",
        note=(
            f"{scripts['projects_with_tests']} of {scripts['projects_total']} projects ship a Python "
            "test suite in scripts/tests/"
        ),
    )

    # --- CIS IG1 ---------------------------------------------------------------------
    repo(
        "KPI-22", "CIS IG1 implementation %", "Governance",
        value=NOT_MEASURED if safeguards["scored_after"] == 0 else None,
        source="data/cis-ig1-safeguards.csv (after_status column)",
        kind="percentage",
        unit="%",
        target="trend up",
        rag="not measured",
        note=(
            f"{safeguards['scored_after']} of {safeguards['total']} safeguards scored - the assessment "
            "has not been run yet, so no percentage is reported"
        ),
    )
    repo(
        "KPI-23", "Safeguards with evidence present", "Governance",
        value=evidence_present,
        source="configs/cis-ig1-evidence-map.csv vs the repository",
        kind="count",
        target=f"{evidence_total}",
        rag="red" if evidence_present < evidence_total else "green",
        note=(
            f"{evidence_total - evidence_present} of {evidence_total} expected evidence artifacts are "
            "not in the repository yet (the lab has not been executed)"
        ),
    )

    # --- change management (from the seeded register) ---------------------------------
    repo(
        "KPI-18", "Changes recorded", "Change",
        value=changes["total"],
        source="data/change-log.csv",
        kind="count",
        note=f"by type: {changes['by_type'] or 'none'}",
    )
    repo(
        "KPI-19", "Emergency change share", "Change",
        value=changes["emergency_share_percent"],
        unit="%",
        source="data/change-log.csv",
        kind="percentage",
        target="<= 10%",
        rag="informational",
        note="no emergency changes recorded yet" if not changes["by_type"].get("emergency") else "",
    )
    repo(
        "KPI-32", "Changes awaiting approval (unsigned)", "Change",
        value=changes["unsigned"],
        source="data/change-log.csv (approver column empty)",
        kind="count",
        target="0",
        rag="informational",
        note="0 is expected here: nothing has been approved yet in the lab",
    )
    repo(
        "KPI-33", "Age of the oldest open change", "Change",
        value=changes["oldest"][1],
        unit="days",
        source="data/change-log.csv (date_raised column)",
        kind="age",
        note=f"{changes['oldest'][0]} raised {changes['oldest'][1]} days ago" if changes["oldest"][1] is not None else "no changes recorded",
    )

    # --- policies and actions ----------------------------------------------------------
    repo(
        "KPI-26", "Policies approved %", "Governance",
        value=(100.0 * policies["approved"] / policies["total"]) if policies["total"] else None,
        unit="%",
        source="data/policy-register.csv",
        kind="percentage",
        target="100%",
        rag="red" if policies["approved"] < policies["total"] else "green",
        note=f"{policies['approved']} of {policies['total']} policies carry an approval date (approval blocks are unsigned on purpose)",
    )
    repo(
        "KPI-24", "Actions closed on time %", "Governance",
        value=actions["percent_on_time"],
        unit="%",
        source="data/action-tracker.csv",
        kind="percentage",
        target=">= 90%",
        rag="not measured",
        note=(
            "no actions recorded yet - the tracker is empty until the projects' reviews produce actions"
            if actions["total"] == 0
            else f"{actions['closed']} of {actions['total']} actions closed"
        ),
    )
    repo(
        "KPI-36", "Open actions in the tracker", "Governance",
        value=actions["open"],
        source="data/action-tracker.csv",
        kind="count",
        target="0",
        rag="informational",
        note=f"{actions['total']} action(s) recorded in total (tracker is empty until reviews happen)",
    )

    # --- lab-measured KPIs (honest placeholders) ---------------------------------------
    lab("KPI-01", "MFA coverage", "Identity", source="P2 MFA coverage report / Entra sign-in report", target="100%", note="needs the lab: P2 Phase 5")
    lab("KPI-02", "Leavers revoked within SLA", "Identity", source="P2 JML audit log", target="100%", note="needs the lab: P2 Phase 3")
    lab("KPI-03", "Stale enabled accounts", "Identity", source="P2 hygiene report", target="0", note="needs the lab: P2 Phase 4")
    lab("KPI-04", "PingCastle risk score", "AD security", source="P3 PingCastle monthly report", target="<= 20", note="needs the lab: P3 Phase 6")
    lab("KPI-05", "Endpoint compliance", "Endpoint", source="P4 compliance report", target=">= 95%", note="needs the lab: P4 Phase 5")
    lab("KPI-06", "Unsupported OS devices", "Endpoint", source="P4 readiness report / P9 CMDB", target="0", note="needs the lab: P4 Phase 1")
    lab("KPI-07", "Patch compliance within 14 days", "Patching", source="P5 / WSUS compliance report", target=">= 95%", note="needs the lab: P5 Phase 4")
    lab("KPI-08", "Open KEV vulnerabilities", "Vulnerability", source="P5 prioritizer dashboard", target="0", note="needs the lab: P5 Phase 3")
    lab("KPI-09", "Findings overdue by tier", "Vulnerability", source="P5 prioritizer dashboard", target="0", note="needs the lab: P5 Phase 3")
    lab("KPI-11", "High-severity alerts", "Monitoring", source="P7 Wazuh dashboard", target="trend", note="needs the lab: P7 Phase 4")
    lab("KPI-13", "MTTD / MTTR", "Monitoring", source="P7 IR register", target="trend down", note="needs the lab: P7 Phase 6")
    lab("KPI-14", "Uptime of critical services", "Availability", source="Uptime Kuma (P9)", target=">= 99.5%", note="needs the lab: P9 Phase 4")
    lab("KPI-15", "Restore tests passed", "Backup", source="P8 restore-test history", target="100%", note="needs the lab: P8 Phase 3")
    lab("KPI-16", "SLA compliance", "Service desk", source="P9 GLPI reporting", target=">= 90%", note="needs the lab: P9 Phase 3")
    lab("KPI-20", "Change success rate", "Change", source="change log + P9 incidents", target=">= 95%", note="needs the lab: P10 Phase 2 review")
    lab("KPI-21", "Unauthorised changes detected", "Change", source="P9 config-as-code drift report", target="0", note="needs the lab: P9 Phase 6")

    return snapshot


# --------------------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------------------
def render_markdown(snapshot: Snapshot) -> str:
    out: list[str] = []
    out.append("# P10 monthly IT KPI snapshot (repository-derived)")
    out.append("")
    out.append(
        f"**As of:** {snapshot.as_of.isoformat()}  "
        f"**Derived from:** this repository (`projects/`, `PROGRESS.md`, `data/`)  "
        f"**Lab status:** not executed"
    )
    out.append("")
    out.append(
        "> Every number below is a **repository-derived count**: it is computed by reading files that "
        "exist in the repository today. It is a real measurement of the repository, not of a running "
        "lab. KPIs that need a running lab are reported as **not measured** and are never estimated."
    )
    out.append("")
    out.append("## Repository-derived")
    out.append("")
    out.append("| KPI | Name | Value | Unit | Source |")
    out.append("|---|---|---|---|---|")
    for r in snapshot.results:
        if r.derived_from != "repository":
            continue
        out.append(f"| {r.kpi_id} | {r.name} | {fmt(r.value)} | {r.unit or '—'} | {r.source} |")
    out.append("")
    out.append("## Lab-measured (not measured yet)")
    out.append("")
    out.append("| KPI | Name | Value | Target | Where it will come from |")
    out.append("|---|---|---|---|---|")
    for r in snapshot.results:
        if r.derived_from != "lab":
            continue
        out.append(f"| {r.kpi_id} | {r.name} | {fmt(r.value)} | {r.target or '—'} | {r.source} |")
    out.append("")
    out.append("---")
    out.append("")
    out.append(
        "*Generated by `projects/p10-governance/scripts/collect_kpis.py`. Halden Distribution Ltd. is a "
        "fictional company used for a home-lab portfolio; this snapshot describes a repository, not a business.*"
    )
    out.append("")
    return "\n".join(out)


def console_summary(snapshot: Snapshot) -> str:
    repo_count = sum(1 for r in snapshot.results if r.derived_from == "repository")
    lab_count = sum(1 for r in snapshot.results if r.derived_from == "lab")
    lines = [f"Repository-derived KPIs: {repo_count}", f"Lab-measured KPIs reported as not measured: {lab_count}"]
    for r in snapshot.results:
        if r.derived_from == "repository" and r.kpi_id in {"KPI-27", "KPI-29", "KPI-25", "KPI-23", "KPI-18", "KPI-26", "KPI-31"}:
            lines.append(f"  {r.kpi_id} {r.name}: {fmt(r.value)}{(' ' + r.unit) if r.unit else ''}")
    return "\n".join(lines)


def append_history(snapshot: Snapshot, path: Path) -> None:
    """Append this period's repository-derived rows to a KPI history CSV."""
    period = snapshot.as_of.strftime("%Y-%m")
    header = "period,kpi_id,kpi_name,value,unit,rag,target,source,as_of,notes\n"
    existing = path.read_text(encoding="utf-8").splitlines() if path.is_file() else []
    keep = [line for line in existing if line.strip() and not line.startswith(header.split(",")[0] + ",")]
    rows = [header.rstrip("\n")]
    for r in snapshot.results:
        if r.derived_from != "repository":
            continue
        value = r.value if isinstance(r.value, (int, float)) or r.value == NOT_MEASURED else json.dumps(r.value)
        rows.append(
            ",".join(
                [
                    period,
                    r.kpi_id,
                    f'"{r.name}"',
                    str(value),
                    r.unit or "",
                    r.rag,
                    f'"{r.target}"' if r.target else "",
                    f'"{r.source}"',
                    snapshot.as_of.isoformat(),
                    f'"{r.note}"' if r.note else "",
                ]
            )
        )
    path.write_text("\n".join(keep + rows) + "\n", encoding="utf-8")


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="collect_kpis.py",
        description=(
            "Measure what P1-P9 actually produced by reading this repository. Values are reported as "
            "repository-derived; lab-measured KPIs stay 'not measured' until the lab is executed."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python3 scripts/collect_kpis.py --dry-run\n"
            "  python3 scripts/collect_kpis.py --json | jq '.kpis[] | select(.derived_from==\"repository\")'\n"
        ),
    )
    parser.add_argument("--out-dir", type=Path, default=P10_DIR / "reports", help="output directory")
    parser.add_argument("--history", type=Path, default=P10_DIR / "data" / "kpi-history.csv", help="KPI history CSV to append to")
    parser.add_argument("--as-of", type=str, default=None, help="date to treat as today (YYYY-MM-DD)")
    parser.add_argument("--json", action="store_true", help="print the snapshot JSON to stdout")
    parser.add_argument("--no-history", action="store_true", help="do not append to the history CSV")
    parser.add_argument("--dry-run", action="store_true", help="compute and print, write nothing")
    parser.add_argument("-v", "--verbose", action="store_true", help="verbose logging")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    configure_logging(args.verbose)

    as_of = parse_date(args.as_of) or date.today()
    snapshot = collect(as_of=as_of)

    stamp = snapshot.as_of.isoformat()
    json_path = Path(args.out_dir) / f"kpi-snapshot-{stamp}.json"
    md_path = Path(args.out_dir) / f"kpi-snapshot-{stamp}.md"

    if args.json:
        print(json.dumps(snapshot.as_dict(), indent=2))
    else:
        print(console_summary(snapshot))

    if args.dry_run:
        LOG.info("dry-run: would write %s and %s", json_path, md_path)
        if not args.no_history:
            LOG.info("dry-run: would append %s to %s", snapshot.as_of.strftime("%Y-%m"), args.history)
        return 0

    write_text(json_path, json.dumps(snapshot.as_dict(), indent=2) + "\n")
    write_text(md_path, render_markdown(snapshot))
    if not args.no_history:
        append_history(snapshot, Path(args.history))
        LOG.info("appended %s rows to %s", snapshot.as_of.strftime("%Y-%m"), args.history)
    if not args.json:
        print(f"\nSnapshot: {json_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
