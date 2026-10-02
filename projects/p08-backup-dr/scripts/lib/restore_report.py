#!/usr/bin/env python3
"""P8 restore-verification report helpers.

Where it applies: BKP01, called by ``scripts/06-Test-BackupRestore.sh`` to append a one-line
history row to the restore-test history CSV, and by the reporting/analysis step to summarise that
history. The logic here is deliberately small and pure so it can be unit-tested without a lab.

No secrets pass through this module: it only reads the JSON result produced by the restore test.
"""

from __future__ import annotations

import argparse
import csv
import json
import logging
import sys
from dataclasses import dataclass, field
from pathlib import Path
from typing import Iterable, Sequence

LOG = logging.getLogger("restore_report")

HISTORY_COLUMNS = [
    "date",
    "host",
    "files_tested",
    "files_matched",
    "mismatches",
    "repo_check",
    "duration_seconds",
    "result",
]


@dataclass(frozen=True)
class RestoreResult:
    """A single weekly restore-test result, parsed from the JSON report."""

    date: str
    host: str
    files_tested: int
    files_matched: int
    mismatches: int
    repo_check: str
    duration_seconds: int
    result: str = ""

    @property
    def pass_rate(self) -> float:
        """Fraction of sampled files that hash-matched (0.0 when nothing was tested)."""
        if self.files_tested <= 0:
            return 0.0
        return self.files_matched / self.files_tested

    def is_pass(self) -> bool:
        """A result passes only when every sampled file matched and the repository check passed."""
        return (
            self.files_tested > 0
            and self.mismatches == 0
            and self.files_matched == self.files_tested
            and self.repo_check.lower() == "pass"
        )

    def to_row(self) -> dict[str, str]:
        return {
            "date": self.date,
            "host": self.host,
            "files_tested": str(self.files_tested),
            "files_matched": str(self.files_matched),
            "mismatches": str(self.mismatches),
            "repo_check": self.repo_check,
            "duration_seconds": str(self.duration_seconds),
            "result": "PASS" if self.is_pass() else "FAIL",
        }


def parse_result(payload: dict) -> RestoreResult:
    """Parse a restore-test JSON payload into a :class:`RestoreResult`.

    Missing counters default to zero, and a missing repository-check status counts as ``unknown``
    (which never passes) rather than silently being treated as a success.
    """

    def as_int(key: str) -> int:
        value = payload.get(key, 0)
        try:
            return int(value)
        except (TypeError, ValueError) as exc:  # pragma: no cover - defensive
            raise ValueError(f"field {key!r} is not an integer: {value!r}") from exc

    date = str(payload.get("date", "")).strip()
    host = str(payload.get("host", "")).strip()
    if not date or not host:
        raise ValueError("restore-test result must contain non-empty 'date' and 'host'")

    return RestoreResult(
        date=date,
        host=host,
        files_tested=as_int("files_tested"),
        files_matched=as_int("files_matched"),
        mismatches=as_int("mismatches"),
        repo_check=str(payload.get("repo_check", "unknown")).strip().lower(),
        duration_seconds=as_int("duration_seconds"),
    )


@dataclass
class HistorySummary:
    """Aggregate view of a restore-test history, for the monthly KPI report."""

    total: int = 0
    passed: int = 0
    failed: int = 0
    consecutive_passes: int = 0
    longest_pass_streak: int = 0
    hosts: set[str] = field(default_factory=set)

    @property
    def success_rate(self) -> float:
        if self.total == 0:
            return 0.0
        return self.passed / self.total


def summarise_rows(rows: Iterable[dict[str, str]]) -> HistorySummary:
    """Summarise history rows in the order given (oldest first)."""

    summary = HistorySummary()
    streak = 0
    for row in rows:
        result = (row.get("result") or "").strip().upper()
        summary.total += 1
        host = (row.get("host") or "").strip()
        if host:
            summary.hosts.add(host)
        if result == "PASS":
            summary.passed += 1
            streak += 1
            summary.longest_pass_streak = max(summary.longest_pass_streak, streak)
        else:
            summary.failed += 1
            streak = 0
    summary.consecutive_passes = streak
    return summary


def append_row(json_path: Path, csv_path: Path) -> RestoreResult:
    """Append the result in ``json_path`` to the history CSV at ``csv_path`` (creating it once)."""

    payload = json.loads(json_path.read_text(encoding="utf-8"))
    result = parse_result(payload)
    csv_path.parent.mkdir(parents=True, exist_ok=True)
    needs_header = not csv_path.exists() or csv_path.stat().st_size == 0
    with csv_path.open("a", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=HISTORY_COLUMNS)
        if needs_header:
            writer.writeheader()
        writer.writerow(result.to_row())
    LOG.info("appended %s result for %s to %s", result.to_row()["result"], result.host, csv_path)
    return result


def read_history(csv_path: Path) -> list[dict[str, str]]:
    """Read a history CSV, ignoring blank lines."""

    with csv_path.open(newline="", encoding="utf-8") as handle:
        return [row for row in csv.DictReader(handle) if any(row.values())]


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="P8 restore-test history helper")
    sub = parser.add_subparsers(dest="command", required=True)

    append = sub.add_parser("append", help="append a JSON result to the history CSV")
    append.add_argument("--json", required=True, type=Path)
    append.add_argument("--csv", required=True, type=Path)
    append.add_argument("--dry-run", action="store_true", help="parse and print, write nothing")

    summary = sub.add_parser("summary", help="summarise a history CSV")
    summary.add_argument("--csv", required=True, type=Path)

    return parser


def main(argv: Sequence[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = _build_parser().parse_args(argv)

    if args.command == "append":
        if args.dry_run:
            payload = json.loads(Path(args.json).read_text(encoding="utf-8"))
            result = parse_result(payload)
            print(json.dumps(result.to_row(), indent=2))
            print("(dry-run) history CSV not modified")
            return 0
        append_row(args.json, args.csv)
        return 0

    if args.command == "summary":
        summary = summarise_rows(read_history(args.csv))
        print(f"tests={summary.total} passed={summary.passed} failed={summary.failed}")
        print(f"success_rate={summary.success_rate:.0%} consecutive_passes={summary.consecutive_passes}")
        print(f"longest_pass_streak={summary.longest_pass_streak} hosts={sorted(summary.hosts)}")
        return 0

    return 1  # pragma: no cover - argparse enforces a command


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
