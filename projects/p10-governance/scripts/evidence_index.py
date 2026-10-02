#!/usr/bin/env python3
"""Index CIS IG1 safeguards against the artifacts that actually evidence them.

Applies to projects/p10-governance.

It joins three things:
  * every safeguard in ``data/cis-ig1-safeguards.csv`` (56 IG1 safeguards);
  * the expected-evidence mapping in ``configs/cis-ig1-evidence-map.csv``;
  * the repository itself - does the named artifact exist right now?

Output
  reports/cis-evidence-index-<date>.md / .csv / .json

Because the lab has not been executed, most expected artifacts do not exist yet. That is the
honest finding: the index reports them as "expected - not present" and never claims a safeguard is
evidenced when no file backs it.
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
    read_csv,
    write_csv,
    write_text,
)

SAFEGUARDS = P10_DIR / "data" / "cis-ig1-safeguards.csv"
EVIDENCE_MAP = P10_DIR / "configs" / "cis-ig1-evidence-map.csv"

PRESENT = "present"
EXPECTED_MISSING = "expected - not present"
NO_PATH = "no artifact path recorded"


@dataclass
class EvidenceRow:
    """One safeguard and the state of its expected evidence."""

    safeguard_id: str
    title: str
    control_id: str
    expected_evidence: str
    source_projects: str
    artifact_path: str
    artifact_kind: str
    state: str
    exists: bool

    def as_dict(self) -> dict[str, object]:
        return {
            "safeguard_id": self.safeguard_id,
            "control_id": self.control_id,
            "title": self.title,
            "expected_evidence": self.expected_evidence,
            "source_projects": self.source_projects,
            "artifact_path": self.artifact_path,
            "artifact_kind": self.artifact_kind,
            "state": self.state,
            "exists": self.exists,
        }


@dataclass
class EvidenceIndex:
    """The whole index plus its derived counts."""

    rows: list[EvidenceRow]
    as_of: date

    @property
    def total(self) -> int:
        return len(self.rows)

    @property
    def present(self) -> int:
        return sum(1 for r in self.rows if r.exists)

    @property
    def missing(self) -> int:
        return self.total - self.present

    def by_source_project(self) -> dict[str, dict[str, int]]:
        """How many safeguards each project is expected to evidence, and how many exist."""
        counts: dict[str, dict[str, int]] = {}
        for row in self.rows:
            for project in [p.strip() for p in row.source_projects.split(";") if p.strip()]:
                entry = counts.setdefault(project, {"expected": 0, "present": 0})
                entry["expected"] += 1
                if row.exists:
                    entry["present"] += 1
        return counts

    def as_dict(self) -> dict[str, object]:
        return {
            "as_of": self.as_of.isoformat(),
            "halden_is_fictional": True,
            "safeguards": self.total,
            "evidence_present": self.present,
            "evidence_expected_but_missing": self.missing,
            "note": (
                "This indexes the repository, not the lab. An artifact 'present' means the file the "
                "evidence map names exists in the repo today; it does not by itself mean the control "
                "is fully implemented."
            ),
            "by_source_project": self.by_source_project(),
            "rows": [r.as_dict() for r in self.rows],
        }


def load_index(
    safeguards_csv: Path = SAFEGUARDS,
    evidence_map_csv: Path = EVIDENCE_MAP,
    *,
    repo_root: Path = REPO_ROOT,
) -> EvidenceIndex:
    if not safeguards_csv.is_file():
        raise FileNotFoundError(f"Safeguard workbook not found: {safeguards_csv}")

    evidence = {r.get("safeguard_id", ""): r for r in read_csv(evidence_map_csv)} if evidence_map_csv.is_file() else {}

    rows: list[EvidenceRow] = []
    for safeguard in read_csv(safeguards_csv):
        sid = (safeguard.get("safeguard_id") or "").strip()
        mapping = evidence.get(sid, {})
        artifact = (mapping.get("artifact_path") or "").strip()
        exists = bool(artifact) and (repo_root / artifact).is_file()
        if not artifact:
            state = NO_PATH
        elif exists:
            state = PRESENT
        else:
            state = EXPECTED_MISSING
        rows.append(
            EvidenceRow(
                safeguard_id=sid,
                title=(safeguard.get("safeguard_title") or "").strip(),
                control_id=(safeguard.get("control_id") or "").strip(),
                expected_evidence=(mapping.get("halden_expected_evidence") or "").strip(),
                source_projects=(mapping.get("source_projects") or "").strip(),
                artifact_path=artifact,
                artifact_kind=(mapping.get("artifact_kind") or "").strip(),
                state=state,
                exists=exists,
            )
        )
    return EvidenceIndex(rows=rows, as_of=date.today())


def render_markdown(index: EvidenceIndex) -> str:
    out: list[str] = []
    out.append("# Halden Distribution Ltd. — CIS IG1 compliance evidence index")
    out.append("")
    out.append(
        f"**As of:** {index.as_of.isoformat()}  "
        f"**Safeguards indexed:** {index.total}  "
        f"**Expected artifacts present today:** {index.present} of {index.total}"
    )
    out.append("")
    out.append(
        "> This indexes the **repository**, not the lab. An artifact is *present* when the file named "
        "in `configs/cis-ig1-evidence-map.csv` exists in this repository today. Because the lab has "
        "not been executed, most artifacts are *expected - not present*: that is the honest state of "
        "an unexecuted build kit, and it is why no safeguard is scored yet."
    )
    out.append("")
    out.append("## Where the evidence will come from")
    out.append("")
    out.append("| Source project | Safeguards it is expected to evidence | Artifacts present today |")
    out.append("|---|---|---|")
    for project, counts in sorted(index.by_source_project().items()):
        label = project if project != "roadmap" else "Gap - 90-day roadmap item"
        out.append(f"| {label} | {counts['expected']} | {counts['present']} |")
    out.append("")
    out.append("## Safeguard by safeguard")
    out.append("")
    out.append("| Safeguard | Title | Expected evidence | Artifact | State |")
    out.append("|---|---|---|---|---|")
    for row in sorted(index.rows, key=lambda r: (int(r.control_id or 0), r.safeguard_id)):
        artifact = row.artifact_path or "—"
        out.append(
            f"| {row.safeguard_id} | {row.title} | {row.expected_evidence or 'not recorded yet'} | "
            f"`{artifact}` | {row.state} |"
        )
    out.append("")
    out.append("## What this does not say")
    out.append("")
    out.append(
        "- It does not score any safeguard. A file existing is one input to a score, `0`–`3`, which a "
        "human writes after reading it."
    )
    out.append(
        "- It does not cover the eight Control 14 safeguards, which depend on a security awareness "
        "programme that does not exist yet. They are recorded as roadmap items."
    )
    out.append("")
    out.append("---")
    out.append("")
    out.append("*Generated by `projects/p10-governance/scripts/evidence_index.py`.*")
    out.append("")
    return "\n".join(out)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="evidence_index.py",
        description="Index each CIS IG1 safeguard against the artifact that will evidence it, and check whether it exists.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--safeguards", type=Path, default=SAFEGUARDS)
    parser.add_argument("--evidence-map", type=Path, default=EVIDENCE_MAP)
    parser.add_argument("--out-dir", type=Path, default=P10_DIR / "reports")
    parser.add_argument("--json", action="store_true", help="print the index JSON to stdout")
    parser.add_argument("--dry-run", action="store_true", help="compute and print, write nothing")
    parser.add_argument("-v", "--verbose", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    configure_logging(args.verbose)
    try:
        index = load_index(args.safeguards, args.evidence_map)
    except FileNotFoundError as exc:
        LOG.error("%s", exc)
        return 2

    stamp = index.as_of.isoformat()
    md_path = Path(args.out_dir) / f"cis-evidence-index-{stamp}.md"
    csv_path = Path(args.out_dir) / f"cis-evidence-index-{stamp}.csv"
    json_path = Path(args.out_dir) / f"cis-evidence-index-{stamp}.json"

    if args.json:
        print(json.dumps(index.as_dict(), indent=2))
    else:
        print(f"CIS IG1 safeguards indexed: {index.total}")
        print(f"Expected evidence artifacts present today: {index.present}")
        print(f"Expected but not present: {index.missing}")
        print(f"By source project: {index.by_source_project()}")

    if args.dry_run:
        LOG.info("dry-run: would write %s, %s and %s", md_path, csv_path, json_path)
        return 0

    write_text(md_path, render_markdown(index))
    write_csv(
        csv_path,
        ["safeguard_id", "control_id", "title", "expected_evidence", "source_projects", "artifact_path", "state"],
        [
            {
                "safeguard_id": r.safeguard_id,
                "control_id": r.control_id,
                "title": r.title,
                "expected_evidence": r.expected_evidence,
                "source_projects": r.source_projects,
                "artifact_path": r.artifact_path,
                "state": r.state,
            }
            for r in index.rows
        ],
    )
    write_text(json_path, json.dumps(index.as_dict(), indent=2) + "\n")
    if not args.json:
        print(f"\nIndex: {md_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
