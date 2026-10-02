"""Generate the SYNTHETIC Halden device fleet for the P4 Windows 11 readiness assessment.

SYNTHETIC DATA NOTICE
---------------------
Every row this script writes is **invented** for the fictional company Halden
Distribution Ltd. The fleet is not a real inventory, the hostnames are not real
machines and no real personal data is used. All figures derived from the file are
synthetic-fleet figures and must be labelled as such (AGENTS.md rule R2).

The output is **deterministic**: the same ``--seed`` and ``--count`` always produce
byte-identical rows, so any count quoted in a report can be reproduced by re-running:

    python3 data/gen_synthetic_fleet.py

It writes two files next to itself:
  * ``synthetic-fleet.csv``      - one row per invented device
  * ``synthetic-fleet-summary.md`` - counts by status and by department (plain
    arithmetic over the CSV, produced here so no number is hand-typed)
"""

from __future__ import annotations

import argparse
import csv
import random
import sys
from collections import Counter, defaultdict
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fleet_rules  # noqa: E402  (co-located module, path added above)

# Staffed departments: (share of the fleet, office). Weighted like a distribution
# company: Operations/Warehouse is the largest group, then Sales, then Finance.
# Shared kiosks and warehouse terminals are assigned separately by device type.
DEPARTMENT_WEIGHTS: list[tuple[str, float, str]] = [
    ("Operations", 0.36, "Warehouse"),
    ("Sales", 0.28, "HQ"),
    ("Finance", 0.14, "HQ"),
    ("HR", 0.07, "HQ"),
    ("Management", 0.08, "HQ"),
    ("IT", 0.07, "HQ"),
]

# Device archetypes. generation 0 means "no supported CPU generation" (Atom/AMD GX).
# os_build is the Windows build number. All hardware values are invented but plausible.
ARCHETYPES: list[dict[str, object]] = [
    {
        "name": "Fleet laptop (modern)",
        "devicetype": "Laptop",
        "model": "Dell Latitude 5540",
        "cpu": "Intel Core i5-1335U",
        "generation": 13,
        "ram": 16,
        "disk": 512,
        "tpm": 2.0,
        "secureboot": "Yes",
        "uefi": "Yes",
        "os": "Windows 11",
        "osbuild": "26100",
        "weight": 18,
    },
    {
        "name": "Fleet desktop (modern)",
        "devicetype": "Desktop",
        "model": "Dell OptiPlex 7010",
        "cpu": "Intel Core i5-13500",
        "generation": 13,
        "ram": 16,
        "disk": 512,
        "tpm": 2.0,
        "secureboot": "Yes",
        "uefi": "Yes",
        "os": "Windows 11",
        "osbuild": "26100",
        "weight": 16,
    },
    {
        "name": "Fleet laptop (recent)",
        "devicetype": "Laptop",
        "model": "HP ProBook 450 G9",
        "cpu": "Intel Core i5-1235U",
        "generation": 12,
        "ram": 16,
        "disk": 256,
        "tpm": 2.0,
        "secureboot": "Yes",
        "uefi": "Yes",
        "os": "Windows 11",
        "osbuild": "22631",
        "weight": 14,
    },
    {
        "name": "Office desktop (recent)",
        "devicetype": "Desktop",
        "model": "Lenovo ThinkCentre M70q Gen 3",
        "cpu": "Intel Core i5-12400T",
        "generation": 12,
        "ram": 8,
        "disk": 256,
        "tpm": 2.0,
        "secureboot": "Yes",
        "uefi": "Yes",
        "os": "Windows 11",
        "osbuild": "22631",
        "weight": 12,
    },
    {
        "name": "Finance desktop (recent)",
        "devicetype": "Desktop",
        "model": "HP EliteDesk 800 G9",
        "cpu": "Intel Core i7-12700",
        "generation": 12,
        "ram": 16,
        "disk": 512,
        "tpm": 2.0,
        "secureboot": "Yes",
        "uefi": "Yes",
        "os": "Windows 11",
        "osbuild": "22631",
        "weight": 8,
    },
    {
        "name": "Entry desktop (Windows 10, capable)",
        "devicetype": "Desktop",
        "model": "Lenovo ThinkCentre M720s",
        "cpu": "Intel Core i3-8100",
        "generation": 8,
        "ram": 8,
        "disk": 256,
        "tpm": 2.0,
        "secureboot": "Yes",
        "uefi": "Yes",
        "os": "Windows 10",
        "osbuild": "19045",
        "weight": 10,
    },
    {
        "name": "Finance laptop (Windows 10, capable)",
        "devicetype": "Laptop",
        "model": "HP EliteBook 840 G5",
        "cpu": "Intel Core i5-8250U",
        "generation": 8,
        "ram": 8,
        "disk": 256,
        "tpm": 2.0,
        "secureboot": "Yes",
        "uefi": "Yes",
        "os": "Windows 10",
        "osbuild": "19045",
        "weight": 9,
    },
    {
        "name": "Small-form desktop (Windows 10, capable)",
        "devicetype": "Desktop",
        "model": "Dell OptiPlex 3070",
        "cpu": "Intel Core i5-9500T",
        "generation": 9,
        "ram": 8,
        "disk": 256,
        "tpm": 2.0,
        "secureboot": "Yes",
        "uefi": "Yes",
        "os": "Windows 10",
        "osbuild": "19045",
        "weight": 7,
    },
    {
        "name": "Warehouse laptop (Windows 10, capable)",
        "devicetype": "Laptop",
        "model": "Dell Latitude 3400",
        "cpu": "Intel Core i3-8145U",
        "generation": 8,
        "ram": 8,
        "disk": 128,
        "tpm": 2.0,
        "secureboot": "Yes",
        "uefi": "Yes",
        "os": "Windows 10",
        "osbuild": "19045",
        "weight": 6,
    },
    {
        "name": "Aged desktop (Windows 10, incapable)",
        "devicetype": "Desktop",
        "model": "HP EliteDesk 800 G3",
        "cpu": "Intel Core i5-7500",
        "generation": 7,
        "ram": 8,
        "disk": 256,
        "tpm": 2.0,
        "secureboot": "Yes",
        "uefi": "Yes",
        "os": "Windows 10",
        "osbuild": "19045",
        "weight": 8,
    },
    {
        "name": "Aged laptop (Windows 10, incapable)",
        "devicetype": "Laptop",
        "model": "Dell Latitude 5480",
        "cpu": "Intel Core i5-7300U",
        "generation": 7,
        "ram": 8,
        "disk": 256,
        "tpm": 2.0,
        "secureboot": "Yes",
        "uefi": "Yes",
        "os": "Windows 10",
        "osbuild": "19045",
        "weight": 6,
    },
    {
        "name": "Legacy desktop (Windows 10, no TPM 2.0)",
        "devicetype": "Desktop",
        "model": "Dell OptiPlex 3020",
        "cpu": "Intel Core i5-4590",
        "generation": 4,
        "ram": 8,
        "disk": 256,
        "tpm": 1.2,
        "secureboot": "No",
        "uefi": "No",
        "os": "Windows 10",
        "osbuild": "19045",
        "weight": 3,
    },
    {
        "name": "Warehouse terminal (incapable)",
        "devicetype": "Warehouse terminal",
        "model": "HP t630 Thin Client",
        "cpu": "AMD GX-420GI",
        "generation": 0,
        "ram": 4,
        "disk": 64,
        "tpm": 1.2,
        "secureboot": "No",
        "uefi": "No",
        "os": "Windows 10",
        "osbuild": "19045",
        "weight": 3,
    },
    {
        "name": "Shared kiosk (incapable)",
        "devicetype": "Kiosk",
        "model": "Lenovo ThinkCentre M700 Tiny",
        "cpu": "Intel Core i3-6100T",
        "generation": 6,
        "ram": 4,
        "disk": 128,
        "tpm": 1.2,
        "secureboot": "Yes",
        "uefi": "Yes",
        "os": "Windows 10",
        "osbuild": "19045",
        "weight": 2,
    },
]

CSV_FIELDS = [
    "AssetID",
    "Hostname",
    "Department",
    "Office",
    "DeviceType",
    "Model",
    "CPU",
    "CPUGeneration",
    "RAM_GB",
    "Disk_GB",
    "TPMVersion",
    "SecureBoot",
    "UEFI",
    "OS",
    "OSBuild",
    "DeviceAgeMonths",
]


def _weighted_choice(rng: random.Random, items: list[tuple[object, float]]) -> object:
    total = sum(weight for _, weight in items)
    pick = rng.uniform(0, total)
    running = 0.0
    for value, weight in items:
        running += weight
        if pick <= running:
            return value
    return items[-1][0]


def generate(count: int, seed: int) -> list[dict[str, object]]:
    """Return ``count`` invented devices as dictionaries (deterministic for a seed)."""
    rng = random.Random(seed)
    archetypes = [(a, float(a["weight"])) for a in ARCHETYPES]
    departments = [(d, w) for d, w, _ in DEPARTMENT_WEIGHTS]
    office_by_dept = {d: o for d, _, o in DEPARTMENT_WEIGHTS}
    rows: list[dict[str, object]] = []

    for index in range(1, count + 1):
        archetype = _weighted_choice(rng, archetypes)
        department = _weighted_choice(rng, departments)
        assert isinstance(archetype, dict) and isinstance(department, str)

        # Shared devices belong to no single department; the rest follow the staffing weights.
        if archetype["devicetype"] == "Warehouse terminal":
            department, office = "Operations", "Warehouse"
        elif archetype["devicetype"] == "Kiosk":
            department, office = "Shared/Kiosk", "Mixed"
        else:
            office = office_by_dept.get(department, "HQ")

        # Small, realistic variation around the archetype.
        age = rng.randint(6, 30) if int(archetype["generation"]) >= 11 else rng.randint(60, 108)
        ram = int(archetype["ram"])
        disk = int(archetype["disk"])
        suffix = f"{index:04d}"

        rows.append(
            {
                "AssetID": f"HQ-{archetype['devicetype'][:2].upper()}-{suffix}",
                "Hostname": f"HQ-{str(archetype['devicetype']).split()[0].upper()}-{suffix}",
                "Department": department,
                "Office": office,
                "DeviceType": archetype["devicetype"],
                "Model": archetype["model"],
                "CPU": archetype["cpu"],
                "CPUGeneration": archetype["generation"],
                "RAM_GB": ram,
                "Disk_GB": disk,
                "TPMVersion": archetype["tpm"],
                "SecureBoot": archetype["secureboot"],
                "UEFI": archetype["uefi"],
                "OS": archetype["os"],
                "OSBuild": archetype["osbuild"],
                "DeviceAgeMonths": age,
            }
        )
    return rows


def summarise(rows: list[dict[str, object]]) -> dict[str, object]:
    """Count rows by status and status-by-department (plain arithmetic over the CSV)."""
    status_counts: Counter[str] = Counter()
    by_department: dict[str, Counter[str]] = defaultdict(Counter)
    reason_counts: Counter[str] = Counter()

    for row in rows:
        status = fleet_rules.classify(row)
        status_counts[status] += 1
        by_department[str(row["Department"])][status] += 1
        for reason in fleet_rules.hardware_failures(row):
            reason_counts[reason] += 1

    return {
        "total": len(rows),
        "status_counts": status_counts,
        "by_department": {dept: dict(counts) for dept, counts in sorted(by_department.items())},
        "reason_counts": reason_counts,
    }


def render_summary(rows: list[dict[str, object]], seed: int) -> str:
    summary = summarise(rows)
    status_counts: Counter[str] = summary["status_counts"]  # type: ignore[assignment]
    by_department: dict[str, dict[str, int]] = summary["by_department"]  # type: ignore[assignment]
    reason_counts: Counter[str] = summary["reason_counts"]  # type: ignore[assignment]
    order = [fleet_rules.READY, fleet_rules.UPGRADE, fleet_rules.REPLACE]

    lines = [
        "# Synthetic fleet readiness summary",
        "",
        "> **SYNTHETIC FLEET.** This summary is produced by `data/gen_synthetic_fleet.py` "
        "from `data/synthetic-fleet.csv`, which is an **invented** device inventory for the "
        "fictional company Halden Distribution Ltd. It is not a real inventory and must be "
        "labelled synthetic wherever it is quoted (AGENTS.md rule R2).",
        "",
        f"- Generated by: `python3 data/gen_synthetic_fleet.py --count {summary['total']} --seed {seed}`",
        f"- Devices in the synthetic fleet: **{summary['total']}**",
        f"- Deterministic: yes (seed `{seed}`)",
        "",
        "## Devices by readiness status (synthetic fleet)",
        "",
        "| Status | Meaning | Devices | Share |",
        "|---|---|---:|---:|",
    ]
    for status in order:
        count = status_counts.get(status, 0)
        share = (count / summary["total"] * 100) if summary["total"] else 0.0
        lines.append(f"| `{status}` | {fleet_rules.STATUS_LABELS[status]} | {count} | {share:.0f}% |")

    lines += [
        "",
        "## Devices by department and status (synthetic fleet)",
        "",
        "| Department | ready | upgrade | replace | Total |",
        "|---|---:|---:|---:|---:|",
    ]
    for dept, counts in by_department.items():
        total = sum(counts.values())
        lines.append(
            f"| {dept} | {counts.get(fleet_rules.READY, 0)} | {counts.get(fleet_rules.UPGRADE, 0)} "
            f"| {counts.get(fleet_rules.REPLACE, 0)} | {total} |"
        )

    lines += [
        "",
        "## Why devices are classified `replace` (synthetic fleet)",
        "",
        "| Hardware requirement not met | Devices affected |",
        "|---|---:|",
    ]
    for reason, count in sorted(reason_counts.items(), key=lambda item: -item[1]):
        lines.append(f"| {reason} | {count} |")

    lines += [
        "",
        "All figures above are percentages and counts computed directly from the synthetic "
        "CSV. No real device was measured, and no number in the management report is an "
        "invented conversion rate.",
        "",
    ]
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Generate the SYNTHETIC Halden device fleet for the P4 Windows 11 assessment."
    )
    parser.add_argument("--count", type=int, default=150, help="number of invented devices (default 150)")
    parser.add_argument("--seed", type=int, default=42, help="random seed; same seed = same file")
    parser.add_argument(
        "--out-dir",
        type=Path,
        default=Path(__file__).resolve().parent,
        help="output directory (default: this folder)",
    )
    parser.add_argument("--dry-run", action="store_true", help="print the summary without writing files")
    args = parser.parse_args()

    if args.count < 1:
        parser.error("--count must be at least 1")

    rows = generate(args.count, args.seed)
    summary_md = render_summary(rows, args.seed)

    if args.dry_run:
        print(summary_md)
        return 0

    args.out_dir.mkdir(parents=True, exist_ok=True)
    csv_path = args.out_dir / "synthetic-fleet.csv"
    with csv_path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=CSV_FIELDS)
        writer.writeheader()
        writer.writerows(rows)

    summary_path = args.out_dir / "synthetic-fleet-summary.md"
    summary_path.write_text(summary_md, encoding="utf-8")

    counts = summarise(rows)["status_counts"]
    print(f"wrote {len(rows)} synthetic devices to {csv_path}")
    print(
        f"ready={counts.get(fleet_rules.READY, 0)} "
        f"upgrade={counts.get(fleet_rules.UPGRADE, 0)} "
        f"replace={counts.get(fleet_rules.REPLACE, 0)}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
