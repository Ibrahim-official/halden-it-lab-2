#!/usr/bin/env python3
"""Build the CIS Controls v8.1 IG1 self-assessment report from the safeguard workbook.

Applies to projects/p10-governance (capstone governance project).

Input
  data/cis-ig1-safeguards.csv         56 IG1 safeguards; status columns empty until a real run
  configs/cis-ig1-evidence-map.csv    how each safeguard is expected to be evidenced

Output
  reports/cis-ig1-assessment-<YYYY-MM-DD>.md   the assessment report, statuses filled from the CSV
  reports/cis-ig1-summary-<YYYY-MM-DD>.json    machine-readable summary

Honesty rules enforced by this script (AGENTS.md R2)
  * The percentage implemented is only computed from safeguards that actually carry a score.
    If nothing is scored yet the script reports "not scored" - never a plausible-looking figure.
  * Before/after percentages are printed only when both columns are scored.
  * The 0-3 scale is the plan's scale: 0 not implemented, 1 partial, 2 implemented on some
    systems, 3 fully implemented and evidenced. A score of 3 REQUIRES an evidence source.

Exit codes
  0 report written   ·   1 validation errors found   ·   2 input problem

Examples
  python3 scripts/cis_assessment.py --dry-run
  python3 scripts/cis_assessment.py --open-errors
"""

from __future__ import annotations

import argparse
import json
import sys
from dataclasses import dataclass, field
from datetime import date
from pathlib import Path

from _common import (
    LOG,
    P10_DIR,
    REPO_ROOT,
    configure_logging,
    fmt,
    read_csv,
    write_csv,
    write_text,
)

SAFEGUARD_CSV = P10_DIR / "data" / "cis-ig1-safeguards.csv"
EVIDENCE_MAP_CSV = P10_DIR / "configs" / "cis-ig1-evidence-map.csv"

EXPECTED_SAFEGUARD_COUNT = 56

STATUS_MEANINGS = {
    0: "Not implemented",
    1: "Partial",
    2: "Implemented on some systems",
    3: "Fully implemented and evidenced",
}


# --------------------------------------------------------------------------------------
# Model
# --------------------------------------------------------------------------------------
@dataclass
class Safeguard:
    """One CIS IG1 safeguard row, with its expected-evidence mapping."""

    safeguard_id: str
    control_id: str
    control_name: str
    title: str
    asset_type: str = ""
    security_function: str = ""
    in_scope: bool = True
    before_status: int | None = None
    after_status: int | None = None
    evidence_source: str = ""
    owner: str = ""
    target_date: str = ""
    notes: str = ""
    expected_evidence: str = ""
    source_projects: str = ""
    artifact_path: str = ""

    @property
    def is_scored(self) -> bool:
        return self.after_status is not None

    @property
    def gap_to_full(self) -> int:
        """Points missing from a perfect 3, using the after score."""
        return 3 - (self.after_status or 0)


@dataclass
class Assessment:
    """The whole assessment: safeguards, validation problems and derived counts."""

    safeguards: list[Safeguard] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)
    as_of: date = field(default_factory=date.today)

    # -- counts -------------------------------------------------------------------------
    @property
    def total(self) -> int:
        return len(self.safeguards)

    @property
    def scored_after(self) -> int:
        return sum(1 for s in self.safeguards if s.after_status is not None)

    @property
    def scored_before(self) -> int:
        return sum(1 for s in self.safeguards if s.before_status is not None)

    def percent(self, which: str) -> float | None:
        """Percent of the maximum possible score (3 x scored safeguards). None if nothing scored."""
        scored = [(s.before_status if which == "before" else s.after_status) for s in self.safeguards]
        values = [v for v in scored if v is not None]
        if not values:
            return None
        return 100.0 * sum(values) / (3 * len(values))

    def by_control(self) -> dict[str, dict[str, object]]:
        """Aggregate per control, counting only scored safeguards."""
        controls: dict[str, dict[str, object]] = {}
        for s in self.safeguards:
            entry = controls.setdefault(
                s.control_id,
                {
                    "control_id": s.control_id,
                    "control_name": s.control_name,
                    "count": 0,
                    "scored": 0,
                    "scored_after": 0,
                    "scored_before": 0,
                    "before_sum": 0,
                    "after_sum": 0,
                    "before_scored": 0,
                    "after_scored": 0,
                },
            )
            entry["count"] = int(entry["count"]) + 1
            if s.after_status is not None:
                entry["scored"] = int(entry["scored"]) + 1
                entry["scored_after"] = int(entry["scored_after"]) + 1
                entry["after_sum"] = int(entry["after_sum"]) + s.after_status
                entry["after_scored"] = int(entry["after_scored"]) + 1
            if s.before_status is not None:
                entry["scored_before"] = int(entry["scored_before"]) + 1
                entry["before_sum"] = int(entry["before_sum"]) + s.before_status
                entry["before_scored"] = int(entry["before_scored"]) + 1
        return controls

    def control_percent(self, control_id: str, which: str) -> float | None:
        entry = self.by_control().get(control_id)
        if not entry:
            return None
        scored = int(entry[f"{which}_scored"])
        if scored == 0:
            return None
        return 100.0 * int(entry[f"{which}_sum"]) / (3 * scored)

    @property
    def evidence_gaps(self) -> list[Safeguard]:
        """Safeguards intended to be evidenced but with no evidence path recorded yet."""
        return [s for s in self.safeguards if s.in_scope and not s.artifact_path]

    @property
    def open_gaps(self) -> list[Safeguard]:
        """Scored safeguards that are not at the full score of 3."""
        return [s for s in self.safeguards if s.is_scored and (s.after_status or 0) < 3]

    def summary(self) -> dict[str, object]:
        return {
            "as_of": self.as_of.isoformat(),
            "halden_is_fictional": True,
            "safeguard_count": self.total,
            "expected_safeguard_count": EXPECTED_SAFEGUARD_COUNT,
            "scored_before": self.scored_before,
            "scored_after": self.scored_after,
            "percent_implemented_before": self.percent("before"),
            "percent_implemented_after": self.percent("after"),
            "percent_implemented_note": (
                "Computed from scored safeguards only (sum of 0-3 scores / (3 x scored)). "
                "None means nothing has been scored yet: the assessment has not been run."
            ),
            "controls": {
                cid: {
                    "control_name": entry["control_name"],
                    "safeguards": entry["count"],
                    "scored_after": entry["scored_after"],
                    "percent_before": self.control_percent(cid, "before"),
                    "percent_after": self.control_percent(cid, "after"),
                }
                for cid, entry in sorted(self.by_control().items(), key=lambda kv: int(kv[0]))
            },
            "errors": self.errors,
            "warnings": self.warnings,
        }


# --------------------------------------------------------------------------------------
# Loading and validation
# --------------------------------------------------------------------------------------
def parse_status(raw: str, context: str, errors: list[str]) -> int | None:
    """Parse a 0-3 status cell; blank means 'not scored yet'."""
    text = (raw or "").strip()
    if text == "":
        return None
    try:
        value = int(float(text))
    except ValueError:
        errors.append(f"{context}: status {raw!r} is not a number between 0 and 3")
        return None
    if value not in STATUS_MEANINGS:
        errors.append(f"{context}: status {value} is outside the 0-3 scale")
        return None
    return value


def load_assessment(
    safeguards_csv: Path = SAFEGUARD_CSV,
    evidence_map_csv: Path = EVIDENCE_MAP_CSV,
) -> Assessment:
    """Load and validate the safeguard workbook against the evidence map."""
    assessment = Assessment()

    if not safeguards_csv.is_file():
        raise FileNotFoundError(f"Safeguard workbook not found: {safeguards_csv}")

    rows = read_csv(safeguards_csv)
    evidence_rows = {r.get("safeguard_id", ""): r for r in read_csv(evidence_map_csv)} if evidence_map_csv.is_file() else {}

    seen: set[str] = set()
    for index, row in enumerate(rows, start=2):
        sid = (row.get("safeguard_id") or "").strip()
        context = f"{safeguards_csv.name}:{index} safeguard {sid or '?'}"
        if not sid:
            assessment.errors.append(f"{context}: missing safeguard_id")
            continue
        if not re_valid_id(sid):
            assessment.errors.append(f"{context}: safeguard_id {sid!r} is not of the form N.N")
        if sid in seen:
            assessment.errors.append(f"{context}: duplicate safeguard_id {sid}")
        seen.add(sid)

        evidence = evidence_rows.get(sid, {})
        if evidence_rows and sid not in evidence_rows:
            assessment.warnings.append(f"{context}: no row in {evidence_map_csv.name}")

        entry = Safeguard(
            safeguard_id=sid,
            control_id=(row.get("control_id") or "").strip(),
            control_name=(row.get("control_name") or "").strip(),
            title=(row.get("safeguard_title") or "").strip(),
            asset_type=(row.get("asset_type") or "").strip(),
            security_function=(row.get("security_function") or "").strip(),
            in_scope=(row.get("in_scope") or "yes").strip().lower() in {"yes", "y", "true", "1"},
            before_status=parse_status(row.get("before_status", ""), context + " before", assessment.errors),
            after_status=parse_status(row.get("after_status", ""), context + " after", assessment.errors),
            evidence_source=(row.get("evidence_source") or "").strip(),
            owner=(row.get("owner") or "").strip(),
            target_date=(row.get("target_date") or "").strip(),
            notes=(row.get("notes") or "").strip(),
            expected_evidence=(evidence.get("halden_expected_evidence") or "").strip(),
            source_projects=(evidence.get("source_projects") or "").strip(),
            artifact_path=(evidence.get("artifact_path") or "").strip(),
        )
        assessment.safeguards.append(entry)

    # Structural validation.
    if len(assessment.safeguards) != EXPECTED_SAFEGUARD_COUNT:
        assessment.errors.append(
            f"{safeguards_csv.name}: expected {EXPECTED_SAFEGUARD_COUNT} IG1 safeguards, found {len(assessment.safeguards)}"
        )
    if len(seen) != len(assessment.safeguards):
        assessment.errors.append(f"{safeguards_csv.name}: duplicate safeguard ids present")

    # Evidence rule: a score of 3 must name an evidence source AND that artifact must exist.
    #
    # `evidence_source` is the human-entered proof; `artifact_path` comes from the evidence map and
    # only says where the proof is *expected* to live. A score of 3 therefore requires the explicit
    # `evidence_source`, and if that source looks like a repository path it must resolve to a real
    # file. An expected-but-absent artifact is not evidence.
    for s in assessment.safeguards:
        for which in ("before", "after"):
            value = s.before_status if which == "before" else s.after_status
            if value != 3:
                continue
            if not s.evidence_source:
                assessment.errors.append(
                    f"safeguard {s.safeguard_id} is scored 3 ({which}) but names no evidence source"
                )
                continue
            source = s.evidence_source
            if "/" in source and not source.startswith("http"):
                if not (REPO_ROOT / source).is_file() and not (P10_DIR / source).is_file():
                    assessment.errors.append(
                        f"safeguard {s.safeguard_id} is scored 3 ({which}) but its evidence source "
                        f"does not exist in the repository: {source}"
                    )
        if s.is_scored and not s.expected_evidence and s.in_scope:
            assessment.warnings.append(f"safeguard {s.safeguard_id}: no expected-evidence note")

    return assessment


def re_valid_id(value: str) -> bool:
    import re

    return bool(re.fullmatch(r"\d+\.\d+", value))


# --------------------------------------------------------------------------------------
# Rendering
# --------------------------------------------------------------------------------------
def render_report(assessment: Assessment) -> str:
    """Render the assessment report as Markdown (PDF-ready; the PDF is produced centrally)."""
    out: list[str] = []
    pct_after = assessment.percent("after")
    pct_before = assessment.percent("before")

    out.append("# Halden Distribution Ltd. — CIS Controls v8.1 IG1 self-assessment")
    out.append("")
    out.append(
        f"> **Status of this report: {'assessment scored' if assessment.scored_after else 'template — no safeguards scored yet'}.** "
        "Halden Distribution Ltd. is a fictional 85-user company used for a home-lab portfolio. "
        "Every score in the table below is written by hand after the named evidence has actually been "
        "seen; a safeguard with no evidence stays blank rather than being scored generously."
    )
    out.append("")
    out.append(f"**As of:** {assessment.as_of.isoformat()}  ")
    out.append(f"**Scope:** all {EXPECTED_SAFEGUARD_COUNT} CIS Controls v8.1 Implementation Group 1 safeguards  ")
    out.append(f"**Scored so far:** {assessment.scored_after} of {assessment.total} (after), {assessment.scored_before} of {assessment.total} (before)  ")
    out.append(f"**Owner:** IT Lead (Halden)  ·  **Review:** quarterly  ")
    out.append("")
    out.append("## 1. Method")
    out.append("")
    out.append("Each safeguard is scored on the plan's four-point scale:")
    out.append("")
    for value, meaning in STATUS_MEANINGS.items():
        out.append(f"- **{value}** — {meaning}")
    out.append("")
    out.append(
        "A score of **3 requires evidence**: the assessment tool refuses to accept a 3 whose row has no "
        "evidence source. **Before** is the inherited Halden state recorded in each project's problem "
        "statement; **after** is the state today, counting only what has a file to prove it."
    )
    out.append("")
    out.append("## 2. Headline result")
    out.append("")
    if pct_after is None:
        out.append(
            "**Not scored yet.** No safeguard carries a score, so the implementation percentage is "
            "deliberately not printed. The bar-chart template in `docs/diagrams/p10-cis-ig1-chart-template.svg` "
            "sits empty for the same reason: a percentage appears here only when the underlying scores exist."
        )
    else:
        out.append(f"- Evidenced implementation **before:** {fmt(pct_before)}% (from {assessment.scored_before} scored safeguards)")
        out.append(f"- Evidenced implementation **after:** {fmt(pct_after)}% (from {assessment.scored_after} scored safeguards)")
        out.append("")
        out.append(f"- Safeguards at the full score of 3: {sum(1 for s in assessment.safeguards if s.after_status == 3)}")
        out.append(f"- Safeguards still below 3: {len(assessment.open_gaps)}")
    out.append("")
    out.append("## 3. Result by control")
    out.append("")
    out.append("| Control | Name | IG1 safeguards | Scored (after) | Before % | After % |")
    out.append("|---|---|---|---|---|---|")
    for cid, entry in sorted(assessment.by_control().items(), key=lambda kv: int(kv[0])):
        before_pct = assessment.control_percent(cid, "before")
        after_pct = assessment.control_percent(cid, "after")
        out.append(
            f"| {cid} | {entry['control_name']} | {entry['count']} | {entry['scored_after']} | "
            f"{fmt(before_pct)} | {fmt(after_pct)} |"
        )
    out.append("")
    out.append("## 4. Safeguard detail")
    out.append("")
    out.append(
        "| Safeguard | Title | In scope | Before | After | Evidence source | Expected evidence (Halden) |"
    )
    out.append("|---|---|---|---|---|---|---|")
    for s in sorted(assessment.safeguards, key=lambda x: (int(x.control_id), x.safeguard_id)):
        out.append(
            f"| {s.safeguard_id} | {s.title} | {'yes' if s.in_scope else 'no'} | "
            f"{fmt(s.before_status)} | {fmt(s.after_status)} | "
            f"{s.evidence_source or '—'} | {s.expected_evidence or 'not recorded yet'} |"
        )
    out.append("")
    out.append("## 5. Gaps and the 90-day roadmap")
    out.append("")
    if not assessment.open_gaps:
        out.append(
            "No scored gaps yet. When the assessment is run, every safeguard scoring below 3 is added "
            "to the risk register (`data/risk-register.csv`) and, if it cannot be fixed inside 90 days, "
            "to the roadmap in the State of IT talk. Control 14 (security awareness) is the expected "
            "largest gap because no awareness programme exists in the build kit."
        )
    else:
        out.append("| Safeguard | Title | After score | Points missing | Expected evidence | Owner | Target date |")
        out.append("|---|---|---|---|---|---|---|")
        for s in sorted(assessment.open_gaps, key=lambda x: (x.after_status or 0, x.safeguard_id)):
            out.append(
                f"| {s.safeguard_id} | {s.title} | {fmt(s.after_status)} | {s.gap_to_full} | "
                f"{s.expected_evidence or '—'} | {s.owner or 'unassigned'} | {s.target_date or 'unset'} |"
            )
    out.append("")
    out.append("## 6. Validation")
    out.append("")
    if assessment.errors:
        out.append(f"**{len(assessment.errors)} error(s) — this report must not be used until they are fixed:**")
        out.append("")
        for error in assessment.errors:
            out.append(f"- {error}")
    else:
        out.append("Validation: clean — every safeguard id is unique, every status is inside the 0–3 scale, and no safeguard is scored 3 without an evidence source.")
    if assessment.warnings:
        out.append("")
        out.append(f"Warnings ({len(assessment.warnings)}):")
        out.append("")
        for warning in assessment.warnings:
            out.append(f"- {warning}")
    out.append("")
    out.append("---")
    out.append("")
    out.append(
        "*Generated by `projects/p10-governance/scripts/cis_assessment.py`. The safeguard list is the "
        "public CIS Controls v8.1 IG1 list (56 safeguards); the official CIS document or the free CSAT "
        "tool is authoritative for wording.*"
    )
    out.append("")
    return "\n".join(out)


def console_summary(assessment: Assessment) -> str:
    """A short, honest console summary."""
    lines = [
        f"CIS IG1 safeguards: {assessment.total} (expected {EXPECTED_SAFEGUARD_COUNT})",
        f"Scored: before {assessment.scored_before}, after {assessment.scored_after}",
        f"Percent implemented (after): {fmt(assessment.percent('after'))}",
        f"Percent implemented (before): {fmt(assessment.percent('before'))}",
        f"Errors: {len(assessment.errors)} · Warnings: {len(assessment.warnings)}",
    ]
    return "\n".join(lines)


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------
def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="cis_assessment.py",
        description=(
            "Build the CIS Controls v8.1 IG1 self-assessment report from "
            "data/cis-ig1-safeguards.csv. Reports 'not scored' until real scores exist."
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  python3 scripts/cis_assessment.py --dry-run\n"
            "  python3 scripts/cis_assessment.py --open-errors\n"
        ),
    )
    parser.add_argument("--safeguards", type=Path, default=SAFEGUARD_CSV, help="safeguard workbook CSV")
    parser.add_argument("--evidence-map", type=Path, default=EVIDENCE_MAP_CSV, help="evidence map CSV")
    parser.add_argument("--out-dir", type=Path, default=P10_DIR / "reports", help="output directory")
    parser.add_argument("--gaps-csv", type=Path, default=None, help="also write the open-gap list to this CSV")
    parser.add_argument("--json", action="store_true", help="print the machine-readable summary to stdout")
    parser.add_argument("--open-errors", action="store_true", help="exit 1 when validation errors are found")
    parser.add_argument("--dry-run", action="store_true", help="validate and print, but write nothing")
    parser.add_argument("-v", "--verbose", action="store_true", help="verbose logging")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    configure_logging(args.verbose)

    try:
        assessment = load_assessment(args.safeguards, args.evidence_map)
    except FileNotFoundError as exc:
        LOG.error("%s", exc)
        return 2

    report = render_report(assessment)
    stamp = assessment.as_of.isoformat()
    report_path = Path(args.out_dir) / f"cis-ig1-assessment-{stamp}.md"
    json_path = Path(args.out_dir) / f"cis-ig1-summary-{stamp}.json"

    if args.dry_run:
        LOG.info("dry-run: would write %s and %s", report_path, json_path)
    else:
        write_text(report_path, report)
        write_text(json_path, json.dumps(assessment.summary(), indent=2) + "\n")
        if args.gaps_csv:
            write_csv(
                Path(args.gaps_csv),
                [
                    "safeguard_id",
                    "title",
                    "after_status",
                    "points_missing",
                    "expected_evidence",
                    "owner",
                    "target_date",
                ],
                [
                    {
                        "safeguard_id": s.safeguard_id,
                        "title": s.title,
                        "after_status": fmt(s.after_status),
                        "points_missing": s.gap_to_full,
                        "expected_evidence": s.expected_evidence,
                        "owner": s.owner,
                        "target_date": s.target_date,
                    }
                    for s in assessment.open_gaps
                ],
            )

    if args.json:
        print(json.dumps(assessment.summary(), indent=2))
    else:
        print(console_summary(assessment))
        if not args.dry_run:
            print(f"\nReport: {report_path}")

    if args.open_errors and assessment.errors:
        LOG.error("validation failed with %d error(s)", len(assessment.errors))
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
