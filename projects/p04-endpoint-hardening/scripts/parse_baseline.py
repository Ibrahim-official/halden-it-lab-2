"""Summarise a baseline-audit export (HardeningKitty / CIS-CAT style CSV) into a report.

P4 Phase 0 and Phase 1 produce a machine-readable baseline result (HardeningKitty's
``-Report`` CSV, or a CIS-CAT Lite export converted to CSV). This script turns that
export into a short pass/fail summary so the "before" and "after" scores in the README
are read from the same file the lab produced, not re-typed.

Expected columns (extra columns are ignored; header names are matched case-insensitively):
    Control   - the finding or control name (required)
    Category  - grouping, for example "BitLocker" or "Windows Defender" (optional)
    Status    - Passed / Failed / Skipped / NotApplicable (required)

The script reports only counts and simple percentages. It does not invent a score: if a
control is "Skipped" it is counted as skipped, not as a pass.

Usage:
    python3 scripts/parse_baseline.py --csv evidence/raw/wks01-before.csv
    python3 scripts/parse_baseline.py --csv after.csv --out reports/baseline-after.md
    python3 scripts/parse_baseline.py --csv before.csv --dry-run
"""

from __future__ import annotations

import argparse
import csv
import logging
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable, Mapping, Sequence

LOGGER = logging.getLogger("parse_baseline")

PASSED = "passed"
FAILED = "failed"
SKIPPED = "skipped"
NOT_APPLICABLE = "notapplicable"

# Normalise the many spellings an audit tool may use.
_STATUS_ALIASES = {
    "pass": PASSED,
    "passed": PASSED,
    "ok": PASSED,
    "true": PASSED,
    "fail": FAILED,
    "failed": FAILED,
    "false": FAILED,
    "skip": SKIPPED,
    "skipped": SKIPPED,
    "na": NOT_APPLICABLE,
    "n/a": NOT_APPLICABLE,
    "notapplicable": NOT_APPLICABLE,
    "not applicable": NOT_APPLICABLE,
}


def normalise_status(value: Any) -> str:
    """Map a raw status cell to one of passed / failed / skipped / notapplicable."""
    key = str(value).strip().lower().replace("_", " ")
    return _STATUS_ALIASES.get(key, FAILED)


def _find_column(fieldnames: Iterable[str], wanted: str) -> str | None:
    for name in fieldnames:
        if name and name.strip().lower() == wanted:
            return name
    return None


def summarise(rows: Iterable[Mapping[str, Any]]) -> dict[str, Any]:
    """Count controls by status, overall and per category."""
    rows = list(rows)
    counts: Counter[str] = Counter()
    by_category: dict[str, Counter[str]] = defaultdict(Counter)

    for row in rows:
        status = normalise_status(row.get("_status", ""))
        counts[status] += 1
        by_category[str(row.get("_category", "Uncategorised"))][status] += 1

    scored = counts[PASSED] + counts[FAILED]
    return {
        "total": len(rows),
        "counts": counts,
        "by_category": dict(sorted(by_category.items())),
        "compliance_percent": round(counts[PASSED] / scored * 100, 1) if scored else 0.0,
    }


def load_rows(path: Path) -> list[dict[str, Any]]:
    """Load a baseline CSV and normalise the Control/Category/Status columns."""
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(filter_comments(handle))
        fieldnames = reader.fieldnames or []
        status_col = _find_column(fieldnames, "status")
        control_col = _find_column(fieldnames, "control") or _find_column(fieldnames, "name")
        category_col = _find_column(fieldnames, "category")
        if status_col is None or control_col is None:
            raise ValueError("baseline CSV needs a 'Status' column and a 'Control' (or 'Name') column")

        rows: list[dict[str, Any]] = []
        for raw in reader:
            rows.append(
                {
                    "_control": raw.get(control_col, ""),
                    "_category": raw.get(category_col, "Uncategorised") if category_col else "Uncategorised",
                    "_status": raw.get(status_col, ""),
                }
            )
        return rows


def filter_comments(lines: Iterable[str]) -> Iterable[str]:
    """Drop blank lines and comment lines so a hand-annotated export still parses."""
    for line in lines:
        if line.strip() and not line.lstrip().startswith("#"):
            yield line


def render_markdown(summary: dict[str, Any], source: str) -> str:
    counts: Counter[str] = summary["counts"]
    lines = [
        "# Baseline audit summary (P4)",
        "",
        f"- Source export: `{source}`",
        f"- Controls assessed: **{summary['total']}**",
        f"- Passed / Failed / Skipped / Not applicable: "
        f"**{counts[PASSED]} / {counts[FAILED]} / {counts[SKIPPED]} / {counts[NOT_APPLICABLE]}**",
        f"- Compliance across scored controls (passed / (passed + failed)): "
        f"**{summary['compliance_percent']}%**",
        "",
        "> This is arithmetic over one audit export. It is only a publishable 'before' or 'after' score once the export itself came from a real run in the lab.",
        "",
        "## By category",
        "",
        "| Category | Passed | Failed | Skipped | Not applicable |",
        "|---|---:|---:|---:|---:|",
    ]
    by_category: dict[str, Counter[str]] = summary["by_category"]
    for category, category_counts in by_category.items():
        lines.append(
            f"| {category} | {category_counts[PASSED]} | {category_counts[FAILED]} "
            f"| {category_counts[SKIPPED]} | {category_counts[NOT_APPLICABLE]} |"
        )
    lines.append("")
    return "\n".join(lines)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--csv", type=Path, required=True, help="baseline audit CSV to summarise")
    parser.add_argument("--out", type=Path, help="write the report here (default: print to stdout)")
    parser.add_argument("--dry-run", action="store_true", help="print the report without writing a file")
    parser.add_argument("--verbose", action="store_true", help="show debug logging")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(levelname)s %(message)s")

    if not args.csv.is_file():
        LOGGER.error("baseline CSV not found: %s", args.csv)
        return 2

    try:
        rows = load_rows(args.csv)
    except ValueError as exc:
        LOGGER.error("%s", exc)
        return 2
    if not rows:
        LOGGER.error("no control rows found in %s", args.csv)
        return 2

    summary = summarise(rows)
    LOGGER.info(
        "assessed %d controls: passed=%d failed=%d skipped=%d",
        summary["total"],
        summary["counts"][PASSED],
        summary["counts"][FAILED],
        summary["counts"][SKIPPED],
    )
    report = render_markdown(summary, str(args.csv))

    if args.out and not args.dry_run:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(report, encoding="utf-8")
        LOGGER.info("wrote report to %s", args.out)
    else:
        print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
