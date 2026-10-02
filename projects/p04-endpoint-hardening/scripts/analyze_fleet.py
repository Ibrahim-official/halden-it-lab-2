"""Read a device fleet CSV and report Windows 11 readiness (P4 Phase 6).

The default input is the **synthetic** fleet in ``data/synthetic-fleet.csv``; the script
also accepts any CSV with the same columns (for example one exported from a real
inventory tool). The classification logic lives in ``data/fleet_rules.py`` so the
generator, this analyzer and the unit tests all use exactly the same rules.

Every figure printed or written is plain arithmetic over the input CSV. Nothing here
measures a real machine.

Usage:
    python3 scripts/analyze_fleet.py                     # report the synthetic fleet
    python3 scripts/analyze_fleet.py --format html --out report.html
    python3 scripts/analyze_fleet.py --dry-run           # print, do not write
"""

from __future__ import annotations

import argparse
import csv
import logging
import sys
from collections import Counter, defaultdict
from pathlib import Path
from typing import Any, Iterable, Sequence

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "data"))
import fleet_rules  # noqa: E402  (path added above)

LOGGER = logging.getLogger("analyze_fleet")

STATUS_ORDER = [fleet_rules.READY, fleet_rules.UPGRADE, fleet_rules.REPLACE]


def load_rows(path: Path) -> list[dict[str, str]]:
    """Load a fleet CSV, skipping blank lines and comment lines starting with '#'."""
    with path.open(newline="", encoding="utf-8") as handle:
        filtered = (line for line in handle if line.strip() and not line.lstrip().startswith("#"))
        return list(csv.DictReader(filtered))


def aggregate(rows: Iterable[dict[str, Any]]) -> dict[str, Any]:
    """Return counts by status, by department-by-status and by failure reason."""
    rows = list(rows)
    status_counts: Counter[str] = Counter()
    by_department: dict[str, Counter[str]] = defaultdict(Counter)
    reason_counts: Counter[str] = Counter()

    for row in rows:
        status = fleet_rules.classify(row)
        status_counts[status] += 1
        by_department[str(row.get("Department", "Unknown"))][status] += 1
        for reason in fleet_rules.hardware_failures(row):
            reason_counts[reason] += 1

    return {
        "total": len(rows),
        "status_counts": status_counts,
        "by_department": dict(sorted(by_department.items())),
        "reason_counts": reason_counts,
    }


def _share(count: int, total: int) -> str:
    return f"{(count / total * 100):.0f}%" if total else "0%"


def render_markdown(summary: dict[str, Any], source: str) -> str:
    total = int(summary["total"])
    status_counts: Counter[str] = summary["status_counts"]
    by_department: dict[str, Counter[str]] = summary["by_department"]
    reason_counts: Counter[str] = summary["reason_counts"]

    lines = [
        "# Windows 11 readiness (P4 Phase 6)",
        "",
        f"- Source file: `{source}`",
        f"- Devices analysed: **{total}**",
        "",
        "> If the source is `data/synthetic-fleet.csv` these figures describe a "
        "**synthetic** fleet (invented for the fictional company Halden Distribution Ltd.) "
        "and must be labelled synthetic wherever they are quoted. No real device was measured.",
        "",
        "## Status (synthetic fleet unless a real inventory was supplied)",
        "",
        "| Status | Meaning | Devices | Share |",
        "|---|---|---:|---:|",
    ]
    for status in STATUS_ORDER:
        count = status_counts.get(status, 0)
        lines.append(f"| `{status}` | {fleet_rules.STATUS_LABELS[status]} | {count} | {_share(count, total)} |")

    lines += [
        "",
        "## By department",
        "",
        "| Department | ready | upgrade | replace | Total |",
        "|---|---:|---:|---:|---:|",
    ]
    for dept, counts in by_department.items():
        dept_total = sum(counts.values())
        lines.append(
            f"| {dept} | {counts.get(fleet_rules.READY, 0)} | {counts.get(fleet_rules.UPGRADE, 0)} "
            f"| {counts.get(fleet_rules.REPLACE, 0)} | {dept_total} |"
        )

    lines += [
        "",
        "## Reasons a device is `replace`",
        "",
        "| Hardware requirement not met | Devices affected |",
        "|---|---:|",
    ]
    for reason, count in sorted(reason_counts.items(), key=lambda item: (-item[1], item[0])):
        lines.append(f"| {reason} | {count} |")
    lines.append("")
    return "\n".join(lines)


def render_html(summary: dict[str, Any], source: str) -> str:
    """Minimal, dependency-free HTML view of the same arithmetic."""
    total = int(summary["total"])
    status_counts: Counter[str] = summary["status_counts"]
    rows = "\n".join(
        f"      <tr><td><code>{status}</code></td><td>{fleet_rules.STATUS_LABELS[status]}</td>"
        f"<td>{status_counts.get(status, 0)}</td><td>{_share(status_counts.get(status, 0), total)}</td></tr>"
        for status in STATUS_ORDER
    )
    return (
        "<!doctype html>\n<html lang=\"en\"><head><meta charset=\"utf-8\">\n"
        "<title>Windows 11 readiness (P4)</title>\n"
        "<style>body{font-family:system-ui,sans-serif;max-width:52rem;margin:2rem auto;padding:0 1rem}"
        "table{border-collapse:collapse;width:100%}th,td{border:1px solid #cbd5e1;padding:.4rem .6rem;text-align:left}</style>"
        "</head><body>\n"
        "<h1>Windows 11 readiness (P4 Phase 6)</h1>\n"
        f"<p>Source file: <code>{source}</code> &middot; devices analysed: <strong>{total}</strong></p>\n"
        "<p><strong>Synthetic fleet notice.</strong> If the source is <code>data/synthetic-fleet.csv</code>, "
        "these figures describe an invented fleet for the fictional company Halden Distribution Ltd. No real "
        "device was measured.</p>\n"
        "<table><thead><tr><th>Status</th><th>Meaning</th><th>Devices</th><th>Share</th></tr></thead>\n"
        f"<tbody>\n{rows}\n</tbody></table>\n"
        "</body></html>\n"
    )


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    default_csv = Path(__file__).resolve().parent.parent / "data" / "synthetic-fleet.csv"
    parser.add_argument("--csv", type=Path, default=default_csv, help="fleet CSV to analyse")
    parser.add_argument("--format", choices=["markdown", "html"], default="markdown")
    parser.add_argument("--out", type=Path, help="write the report here (default: print to stdout)")
    parser.add_argument("--dry-run", action="store_true", help="print the report without writing a file")
    parser.add_argument("--verbose", action="store_true", help="show debug logging")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(level=logging.DEBUG if args.verbose else logging.INFO, format="%(levelname)s %(message)s")

    if not args.csv.is_file():
        LOGGER.error("fleet CSV not found: %s", args.csv)
        return 2

    rows = load_rows(args.csv)
    if not rows:
        LOGGER.error("no device rows found in %s", args.csv)
        return 2

    summary = aggregate(rows)
    LOGGER.info(
        "analysed %d devices: ready=%d upgrade=%d replace=%d",
        summary["total"],
        summary["status_counts"].get(fleet_rules.READY, 0),
        summary["status_counts"].get(fleet_rules.UPGRADE, 0),
        summary["status_counts"].get(fleet_rules.REPLACE, 0),
    )
    report = render_html(summary, str(args.csv)) if args.format == "html" else render_markdown(summary, str(args.csv))

    if args.out and not args.dry_run:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(report, encoding="utf-8")
        LOGGER.info("wrote report to %s", args.out)
    else:
        print(report)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
