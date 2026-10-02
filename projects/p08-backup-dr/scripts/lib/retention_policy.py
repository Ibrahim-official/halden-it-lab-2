#!/usr/bin/env python3
"""P8 retention-policy calculator.

Where it applies: BKP01, used by ``scripts/10-Get-BackupReport.sh`` and the documentation build to
turn a retention policy into concrete ``restic forget`` arguments and to answer the two questions an
auditor asks: *how far back can we restore?* and *is the immutable floor at least the recovery window?*

The policy is data, not code: pass a JSON file (see ``configs/p08-backup-jobs.yaml`` for the values)
or use the built-in Halden defaults so the module is testable on its own.
"""

from __future__ import annotations

import argparse
import json
import logging
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence

LOG = logging.getLogger("retention_policy")

# Designed Halden policy (configs/p08-backup-jobs.yaml `retention:`). Kept here as the default so the
# calculator can be unit-tested and used offline; the YAML remains the source of truth for the lab.
DEFAULT_POLICY: dict[str, dict[str, int]] = {
    "tier0": {"daily": 30, "monthly": 12, "immutable_floor_days": 30, "recovery_window_days": 30},
    "tier1": {"hourly": 24, "daily": 14, "weekly": 8, "monthly": 12, "immutable_floor_days": 30, "recovery_window_days": 30},
    "tier2": {"daily": 14, "weekly": 8, "immutable_floor_days": 30, "recovery_window_days": 30},
}

# restic --keep-* flags, in the order restic documents them.
_KEEP_FLAGS = (
    ("hourly", "--keep-hourly"),
    ("daily", "--keep-daily"),
    ("weekly", "--keep-weekly"),
    ("monthly", "--keep-monthly"),
    ("yearly", "--keep-yearly"),
)


@dataclass(frozen=True)
class Tier:
    """Retention for one tier, plus the immutability guarantee attached to it."""

    name: str
    keep: dict[str, int]
    immutable_floor_days: int
    recovery_window_days: int

    def oldest_restore_point_days(self) -> int:
        """How far back the retention actually reaches, in days.

        Monthly is treated as 30 days and yearly as 365, which is the conservative convention: it
        never over-claims the recovery window.
        """

        reach = 0
        if self.keep.get("hourly"):
            reach = max(reach, 1)
        if self.keep.get("daily"):
            reach = max(reach, self.keep["daily"])
        if self.keep.get("weekly"):
            reach = max(reach, self.keep["weekly"] * 7)
        if self.keep.get("monthly"):
            reach = max(reach, self.keep["monthly"] * 30)
        if self.keep.get("yearly"):
            reach = max(reach, self.keep["yearly"] * 365)
        return reach

    def forget_arguments(self) -> str:
        """The ``restic forget`` argument string for this tier."""

        parts = [f"{flag} {self.keep[key]}" for key, flag in _KEEP_FLAGS if self.keep.get(key)]
        if not parts:
            raise ValueError(f"tier {self.name!r} keeps nothing - that is not a valid policy")
        return " ".join(parts + ["--prune"])

    def retention_meets_recovery_window(self) -> bool:
        return self.oldest_restore_point_days() >= self.recovery_window_days

    def immutable_floor_ok(self) -> bool:
        """The immutable floor must be at least the recovery window promised to the business."""

        return self.immutable_floor_days >= self.recovery_window_days


def parse_policy(data: dict) -> dict[str, Tier]:
    """Turn a raw policy mapping into :class:`Tier` objects, validating the counts."""

    tiers: dict[str, Tier] = {}
    for name, raw in data.items():
        keep = {k: int(v) for k, v in raw.items() if k in {flag.replace("--keep-", "") for _, flag in _KEEP_FLAGS}}
        if any(v < 0 for v in keep.values()):
            raise ValueError(f"tier {name!r} has a negative retention count")
        tiers[name] = Tier(
            name=name,
            keep=keep,
            immutable_floor_days=int(raw.get("immutable_floor_days", 0)),
            recovery_window_days=int(raw.get("recovery_window_days", 0)),
        )
    return tiers


def audit(tiers: dict[str, Tier]) -> list[str]:
    """Return human-readable warnings; an empty list means the policy is internally consistent."""

    warnings: list[str] = []
    for tier in tiers.values():
        if not tier.retention_meets_recovery_window():
            warnings.append(
                f"{tier.name}: retention reaches only {tier.oldest_restore_point_days()}d "
                f"but the promised recovery window is {tier.recovery_window_days}d"
            )
        if not tier.immutable_floor_ok():
            warnings.append(
                f"{tier.name}: immutable floor {tier.immutable_floor_days}d is shorter than the "
                f"recovery window {tier.recovery_window_days}d - an attacker could delete data the "
                f"business was promised"
            )
    return warnings


def load_policy(path: Path | None) -> dict[str, Tier]:
    if path is None:
        return parse_policy(DEFAULT_POLICY)
    return parse_policy(json.loads(path.read_text(encoding="utf-8")))


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="P8 retention-policy calculator")
    parser.add_argument("--policy", type=Path, help="JSON policy file (defaults to the Halden design)")
    parser.add_argument("--audit", action="store_true", help="only print warnings")
    parser.add_argument("--dry-run", action="store_true", help="print the plan, change nothing")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
    args = _build_parser().parse_args(argv)

    tiers = load_policy(args.policy)
    warnings = audit(tiers)
    if args.dry_run:
        LOG.info("dry-run: no repository commands are executed by this tool")

    for name in sorted(tiers):
        tier = tiers[name]
        print(f"{name}: {tier.forget_arguments()}")
        print(
            f"    oldest restore point: {tier.oldest_restore_point_days()}d "
            f"(recovery window {tier.recovery_window_days}d, "
            f"immutable floor {tier.immutable_floor_days}d)"
        )

    for warning in warnings:
        LOG.warning(warning)
        print(f"WARNING: {warning}")

    # Non-zero exit only when auditing, so the CI/check step can gate on it without breaking reports.
    return 1 if (args.audit and warnings) else 0


if __name__ == "__main__":  # pragma: no cover
    sys.exit(main())
