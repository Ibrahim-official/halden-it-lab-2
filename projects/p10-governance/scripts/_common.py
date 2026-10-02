#!/usr/bin/env python3
"""Shared helpers for the P10 governance tooling.

Applies to projects/p10-governance. Kept deliberately dependency-free (standard library only) so
the tooling runs anywhere the repository is checked out. Nothing in here writes to the lab: these
are repository-side utilities. The lab-facing collectors live in the .sh/.ps1 scripts.

Conventions used across the P10 CSV files:
  * a line whose first non-whitespace character is "#" is a comment header and is skipped;
  * a blank line is skipped;
  * the first non-comment line is the header row.

Halden Distribution Ltd. is fictional; the files these helpers read describe a home lab.
"""

from __future__ import annotations

import csv
import json
import logging
import re
import sys
from dataclasses import dataclass, field
from datetime import date, datetime
from pathlib import Path
from typing import Any, Iterable, Iterator, Sequence

LOG = logging.getLogger("p10")

COMMENT_PREFIX = "#"


# --------------------------------------------------------------------------------------
# Repository discovery
# --------------------------------------------------------------------------------------
def find_repo_root(start: Path | None = None) -> Path:
    """Return the halden-it-lab repository root.

    Walks up from *start* (or this file) until it finds a directory that contains both
    ``AGENTS.md`` and a ``projects/`` directory. Raises ``FileNotFoundError`` otherwise, so a
    script copied out of the repository fails loudly instead of guessing.
    """
    here = (start or Path(__file__).resolve())
    if here.is_file():
        here = here.parent
    for candidate in [here, *here.parents]:
        if (candidate / "AGENTS.md").is_file() and (candidate / "projects").is_dir():
            return candidate
    raise FileNotFoundError(
        "Could not locate the halden-it-lab repository root "
        "(looked for AGENTS.md and projects/ above %s)." % here
    )


REPO_ROOT = find_repo_root()
P10_DIR = REPO_ROOT / "projects" / "p10-governance"
PROJECTS_DIR = REPO_ROOT / "projects"


# --------------------------------------------------------------------------------------
# Logging
# --------------------------------------------------------------------------------------
def configure_logging(verbose: bool = False) -> None:
    """Configure a simple stderr logger (INFO, or DEBUG with *verbose*)."""
    logging.basicConfig(
        level=logging.DEBUG if verbose else logging.INFO,
        format="%(levelname)s %(name)s: %(message)s",
        stream=sys.stderr,
    )


# --------------------------------------------------------------------------------------
# Reading
# --------------------------------------------------------------------------------------
def read_text(path: Path) -> str:
    """Read a UTF-8 text file."""
    return path.read_text(encoding="utf-8")


def read_csv(path: Path) -> list[dict[str, str]]:
    """Read a P10 CSV, skipping ``#`` comment lines and blank lines.

    Returns a list of dictionaries keyed by the header row. Values are stripped.
    """
    lines = [
        line
        for line in path.read_text(encoding="utf-8").splitlines()
        if line.strip() and not line.lstrip().startswith(COMMENT_PREFIX)
    ]
    if not lines:
        return []
    reader = csv.DictReader(lines)
    rows: list[dict[str, str]] = []
    for raw in reader:
        row: dict[str, str] = {}
        for key, value in raw.items():
            name = (key or "").strip()
            if isinstance(value, list):
                # A row with more fields than the header collects the extras in None's list;
                # join them so the row is still readable rather than silently dropped.
                cell = ",".join(str(part).strip() for part in value)
            else:
                cell = (value or "").strip()
            row[name] = cell
        rows.append(row)
    return rows


def read_frontmatter(text: str) -> tuple[str, str]:
    """Split a Markdown file into (frontmatter, body). Frontmatter excludes the --- fences."""
    if not text.startswith("---"):
        return "", text
    match = re.match(r"^---\s*\n(.*?)\n---\s*\n?", text, flags=re.DOTALL)
    if not match:
        return "", text
    return match.group(1), text[match.end():]


def frontmatter_scalar(frontmatter: str, key: str) -> str | None:
    """Return a top-level scalar ``key: value`` from simple frontmatter, else None."""
    match = re.search(rf"^{re.escape(key)}:\s*(.+?)\s*$", frontmatter, flags=re.MULTILINE)
    if not match:
        return None
    return match.group(1).strip().strip('"').strip("'")


def has_top_level_key(frontmatter: str, key: str) -> bool:
    """True if the frontmatter has a top-level ``key:`` entry (scalar or block)."""
    return re.search(rf"^{re.escape(key)}:", frontmatter, flags=re.MULTILINE) is not None


def yaml_list_block(path: Path, block_name: str) -> list[str]:
    """Return the scalar items of a simple ``block_name:`` list in a YAML file.

    Handles the small, flat structures used in ``configs/``::

        required_fields:
          - change_id
          - title            # trailing comment is stripped

    It is not a general YAML parser and says so, rather than pretending.
    """
    items: list[str] = []
    in_block = False
    for line in path.read_text(encoding="utf-8").splitlines():
        if re.match(rf"^{re.escape(block_name)}\s*:\s*(\[\s*\])?\s*$", line):
            in_block = True
            continue
        if not in_block:
            continue
        if re.match(r"^[^\s#].*:", line):  # next top-level key ends the block
            break
        stripped = line.strip()
        if not stripped or stripped.startswith("#"):
            continue
        if stripped.startswith("- "):
            value = stripped[2:].split("#", 1)[0].strip()
            if value:
                items.append(value)
    return items


# --------------------------------------------------------------------------------------
# Dates
# --------------------------------------------------------------------------------------
def parse_date(value: str | None) -> date | None:
    """Parse an ISO date (YYYY-MM-DD), returning None for empty or unparseable values."""
    if not value:
        return None
    try:
        return datetime.strptime(value.strip()[:10], "%Y-%m-%d").date()
    except ValueError:
        return None


def age_days(then: date | None, *, today: date | None = None) -> int | None:
    """Age of *then* in whole days relative to *today* (defaults to today)."""
    if then is None:
        return None
    reference = today or date.today()
    return (reference - then).days


# --------------------------------------------------------------------------------------
# Writing
# --------------------------------------------------------------------------------------
def write_text(path: Path, content: str, *, dry_run: bool = False) -> None:
    """Write a text file, creating parents. In dry-run mode, log and do not touch the disk."""
    if dry_run:
        LOG.info("dry-run: would write %s (%d bytes)", path, len(content))
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8")
    LOG.info("wrote %s", path)


def write_json(path: Path, data: Any, *, dry_run: bool = False) -> None:
    """Write pretty JSON with a trailing newline."""
    write_text(path, json.dumps(data, indent=2, sort_keys=False) + "\n", dry_run=dry_run)


def write_csv(path: Path, fieldnames: Sequence[str], rows: Iterable[dict[str, Any]]) -> None:
    """Write a CSV file (parents created). Blank values are left empty, never invented."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(fieldnames))
        writer.writeheader()
        for row in rows:
            writer.writerow({key: row.get(key, "") for key in fieldnames})


# --------------------------------------------------------------------------------------
# Formatting
# --------------------------------------------------------------------------------------
def fmt(value: Any) -> str:
    """Format a value for Markdown/HTML: None or '' becomes 'not measured'."""
    if value is None:
        return "not measured"
    if isinstance(value, bool):
        return "yes" if value else "no"
    if isinstance(value, float):
        return f"{value:.1f}"
    if value == "":
        return "not measured"
    return str(value)


def bar(value: int, maximum: int, width: int = 20) -> str:
    """A tiny text bar for the console summary (no numeric claim, just scale)."""
    if maximum <= 0:
        return ""
    filled = round(width * value / maximum)
    return "#" * filled + "." * (width - filled)
