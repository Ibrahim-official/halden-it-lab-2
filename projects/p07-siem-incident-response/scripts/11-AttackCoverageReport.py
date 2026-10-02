#!/usr/bin/env python3
"""P7 detection-coverage report (command-line entry point).

Reads an ATT&CK mapping CSV and a Wazuh alert extract and writes a coverage report. It reports
only what the alert file contains; it never invents a hit (AGENTS.md rule R2).

Examples:
    python3 11-AttackCoverageReport.py --mapping ../data/attack-mapping.csv \
        --alerts ../evidence/raw/p07-ph3-detection-raw-extract.json --window-minutes 60
    python3 11-AttackCoverageReport.py --alerts alerts.json --dry-run
"""

from __future__ import annotations

import argparse
import datetime as dt
import logging
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from attack_coverage import (  # noqa: E402  (path inserted above)
    coverage_rows,
    load_mapping,
    render_markdown,
    summarise,
    write_csv,
)

DEFAULT_MAPPING = Path(__file__).resolve().parent.parent / "data" / "attack-mapping.csv"


def parse_args(argv: list[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Build the Halden P7 detection-coverage report.")
    parser.add_argument("--mapping", type=Path, default=DEFAULT_MAPPING, help="ATT&CK mapping CSV.")
    parser.add_argument("--alerts", type=Path, required=True, help="Wazuh alerts JSON-lines extract.")
    parser.add_argument("--window-minutes", type=int, default=60,
                        help="Only count alerts newer than this many minutes (default 60).")
    parser.add_argument("--out-csv", type=Path, default=None, help="Write the coverage CSV here.")
    parser.add_argument("--out-md", type=Path, default=None, help="Write the markdown report here.")
    parser.add_argument("--dry-run", action="store_true", help="Print the report; write no files.")
    parser.add_argument("--verbose", action="store_true", help="Verbose logging.")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )
    if not args.mapping.is_file():
        logging.error("Mapping file not found: %s", args.mapping)
        return 2
    if not args.alerts.is_file():
        logging.error("Alerts file not found: %s", args.alerts)
        return 2

    mapping = load_mapping(args.mapping)
    since = dt.datetime.now(dt.timezone.utc) - dt.timedelta(minutes=args.window_minutes)
    results = summarise(args.alerts, since=since)
    rows = coverage_rows(mapping, results)
    window_description = f"last {args.window_minutes} minutes"
    report = render_markdown(rows, window_description)

    print(report)
    logging.info("Mapped rules: %d ; fired in window: %d", len(rows), sum(1 for r in rows if r["validated"] == "yes"))

    if args.dry_run:
        logging.info("Dry run: no files written.")
        return 0
    if args.out_csv:
        write_csv(rows, args.out_csv)
        logging.info("Wrote %s", args.out_csv)
    if args.out_md:
        args.out_md.parent.mkdir(parents=True, exist_ok=True)
        args.out_md.write_text(report + "\n", encoding="utf-8")
        logging.info("Wrote %s", args.out_md)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
