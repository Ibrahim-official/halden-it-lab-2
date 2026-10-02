#!/usr/bin/env python3
"""Turn P6 segmentation test output into a report and a verification matrix.

The lab runs ``scripts/09-Test-Segmentation.sh`` and ``scripts/11-Test-GuestIotIsolation.sh``, which
write CSV results in the shape ``test_id,source_zone,source_host,destination,port,expected,observed,
result,checked_at``. This tool reads those files, counts passes and failures, groups the outcome by
zone, and writes both a Markdown report and a matrix CSV that maps each expected rule outcome to a
real result.

Nothing here invents a result. If no result files exist, the report says so and stops: an empty
report is correct output before the lab run.

Usage::

    python3 segmentation_report.py --results ../../evidence/public --out /tmp/p6report
    python3 segmentation_report.py --results ./evidence --dry-run
"""

from __future__ import annotations

import argparse
import csv
import logging
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable

LOGGER = logging.getLogger("p06.segmentation_report")

# Observed states a probe can produce. A "blocked" expectation is satisfied by any of the second,
# third or fourth: the packet did not reach an open service.
OPEN = "open"
BLOCKED_STATES = {"closed", "filtered", "unreachable"}


@dataclass(frozen=True)
class TestRow:
    """One attempted connection from the test plan."""

    test_id: str
    source_zone: str
    source_host: str
    destination: str
    port: str
    expected: str
    observed: str
    result: str
    checked_at: str = ""

    @property
    def zone(self) -> str:
        return self.source_zone.strip().upper()


@dataclass
class ZoneSummary:
    """Per-zone totals for the report."""

    zone: str
    total: int = 0
    passed: int = 0
    failed: int = 0
    failures: list[TestRow] = field(default_factory=list)

    @property
    def ratio(self) -> str:
        return f"{self.passed}/{self.total}"


def classify(expected: str, observed: str) -> str:
    """Return PASS or FAIL for one observation against its expectation.

    ``open`` passes only when the port is genuinely open. ``blocked`` (and anything that is not
    ``open``) passes when the port is closed, filtered or unreachable - a service that cannot be
    reached is a blocked service, and a filtered port is what a firewall rule looks like from
    outside.
    """
    expected_norm = expected.strip().lower()
    observed_norm = observed.strip().lower()
    if expected_norm == OPEN:
        return "PASS" if observed_norm == OPEN else "FAIL"
    return "FAIL" if observed_norm == OPEN else "PASS"


def is_comment(line: str) -> bool:
    return line.lstrip().startswith("#")


def parse_results(path: Path) -> list[TestRow]:
    """Parse one results CSV into rows, skipping comment lines and the header."""
    rows: list[TestRow] = []
    with path.open(newline="", encoding="utf-8") as handle:
        filtered = (line for line in handle if not is_comment(line))
        reader = csv.DictReader(filtered)
        required = {"test_id", "source_zone", "source_host", "destination", "port", "expected",
                    "observed", "result"}
        if reader.fieldnames is None or not required.issubset(set(reader.fieldnames)):
            LOGGER.warning("skipping %s: not a P6 results file (columns: %s)", path.name,
                           reader.fieldnames)
            return rows
        for raw in reader:
            rows.append(
                TestRow(
                    test_id=(raw.get("test_id") or "").strip(),
                    source_zone=(raw.get("source_zone") or "").strip(),
                    source_host=(raw.get("source_host") or "").strip(),
                    destination=(raw.get("destination") or "").strip(),
                    port=(raw.get("port") or "").strip(),
                    expected=(raw.get("expected") or "").strip(),
                    observed=(raw.get("observed") or "").strip(),
                    result=(raw.get("result") or "").strip().upper(),
                    checked_at=(raw.get("checked_at") or "").strip(),
                )
            )
    return rows


def collect_rows(results_dir: Path) -> list[TestRow]:
    """Read every ``*segmentation-results*.csv`` and ``*isolation*.csv`` under a directory."""
    rows: list[TestRow] = []
    for pattern in ("*segmentation-results*.csv", "*isolation*.csv"):
        for path in sorted(results_dir.glob(pattern)):
            LOGGER.info("reading %s", path)
            rows.extend(parse_results(path))
    return rows


def summarise(rows: Iterable[TestRow]) -> dict[str, ZoneSummary]:
    """Group rows by zone and count the outcomes, recounting the verdict locally.

    The verdict is recomputed from ``expected``/``observed`` rather than trusted, so a hand-edited
    PASS in the CSV cannot silently pass a report.
    """
    summaries: dict[str, ZoneSummary] = {}
    for row in rows:
        summary = summaries.setdefault(row.zone, ZoneSummary(zone=row.zone))
        summary.total += 1
        verdict = classify(row.expected, row.observed)
        if verdict == "PASS":
            summary.passed += 1
        else:
            summary.failed += 1
            summary.failures.append(row)
    return summaries


def render_markdown(summaries: dict[str, ZoneSummary], total_rows: int) -> str:
    """Render the Markdown report body."""
    lines: list[str] = [
        "# P6 segmentation verification report",
        "",
        "Generated by `scripts/report/segmentation_report.py` from the results files in "
        "`evidence/`.",
        "",
    ]
    if total_rows == 0:
        lines += [
            "**No results yet.** No segmentation result files were found, so there is nothing to "
            "report.",
            "",
            "Run `scripts/09-Test-Segmentation.sh --zone <ZONE>` from a host in each zone first. An "
            "empty report is the correct output before the lab run: this project does not publish "
            "numbers it has not measured.",
        ]
        return "\n".join(lines) + "\n"

    grand_total = sum(s.total for s in summaries.values())
    grand_pass = sum(s.passed for s in summaries.values())
    lines += [
        f"**Overall: {grand_pass}/{grand_total} connections behaved as the rule matrix says.**",
        "",
        "A `blocked` expectation passes when the port is closed, filtered or unreachable. An "
        "`open` expectation passes only when the port is genuinely open.",
        "",
        "| Zone | Result | Failed |",
        "|---|---|---|",
    ]
    for zone in sorted(summaries):
        summary = summaries[zone]
        lines.append(f"| {zone} | {summary.ratio} | {summary.failed} |")

    all_failures = [f for s in summaries.values() for f in s.failures]
    lines += ["", "## Failures", ""]
    if not all_failures:
        lines.append("None: every attempt in the plan matched its expectation.")
    else:
        lines += [
            "| Test | Zone | Destination | Port | Expected | Observed |",
            "|---|---|---|---|---|---|",
        ]
        for f in all_failures:
            lines.append(
                f"| {f.test_id} | {f.zone} | {f.destination} | {f.port} | {f.expected} | {f.observed} |"
            )
        lines += [
            "",
            "Each of these is either an unwanted hole in the rule set or an unwanted block. Review "
            "the firewall log for the matching deny, correct through a change record, and re-run "
            "the suite.",
        ]
    return "\n".join(lines) + "\n"


def write_matrix(summaries: dict[str, ZoneSummary], out_path: Path) -> None:
    """Write a verification matrix CSV: zone -> pass/total/failed."""
    out_path.parent.mkdir(parents=True, exist_ok=True)
    with out_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(["# P6 verification matrix - generated by segmentation_report.py"])
        writer.writerow(["zone", "total", "passed", "failed", "result"])
        for zone in sorted(summaries):
            summary = summaries[zone]
            writer.writerow([zone, summary.total, summary.passed, summary.failed, summary.ratio])


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Summarise P6 segmentation test results into a report and a matrix."
    )
    parser.add_argument("--results", type=Path, default=Path("evidence/public"),
                        help="directory holding the results CSVs (default: evidence/public)")
    parser.add_argument("--out", type=Path, default=Path("evidence/public"),
                        help="directory for the generated report and matrix")
    parser.add_argument("--dry-run", action="store_true",
                        help="parse and summarise but write nothing")
    parser.add_argument("--verbose", "-v", action="store_true", help="debug logging")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
    )

    if not args.results.is_dir():
        LOGGER.error("results directory not found: %s", args.results)
        return 2

    rows = collect_rows(args.results)
    summaries = summarise(rows)
    report = render_markdown(summaries, len(rows))

    if args.dry_run:
        LOGGER.info("dry-run: %d rows parsed across %d zone(s); nothing written",
                    len(rows), len(summaries))
        sys.stdout.write(report)
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    report_path = args.out / "p06-segmentation-report.md"
    matrix_path = args.out / "p06-segmentation-verification-matrix.csv"
    report_path.write_text(report, encoding="utf-8")
    if summaries:
        write_matrix(summaries, matrix_path)
    LOGGER.info("wrote %s and %s", report_path, matrix_path)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
