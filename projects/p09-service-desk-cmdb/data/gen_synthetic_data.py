#!/usr/bin/env python3
"""Generate the SYNTHETIC datasets used by P9 (assets and tickets).

Everything this script writes is synthetic. The names, ticket subjects, serials
and costs are invented for the fictional company Halden Distribution Ltd. and
are NOT real people, devices or purchases. They are labelled synthetic in every
row (a ``Synthetic`` column) and must be labelled synthetic wherever they appear.

Outputs (in this folder):
    halden-assets.csv   - synthetic CMDB asset inventory (computers, servers,
                          printers, network gear, peripherals) for import into
                          GLPI and for the reconciliation tests.
    halden-tickets.csv  - a synthetic support-request export (4 simulated weeks),
                          produced by the same deterministic generator that seeds
                          GLPI (scripts/04-seed-synthetic-tickets.py).

Run:
    python3 gen_synthetic_data.py
"""

from __future__ import annotations

import csv
import datetime as dt
import importlib.util
import json
import pathlib
import random
import sys

HERE = pathlib.Path(__file__).resolve().parent
PROJECT = HERE.parent
TICKET_SCRIPT = PROJECT / "scripts" / "04-seed-synthetic-tickets.py"
CATALOGUE = PROJECT / "configs" / "glpi-cmdb-categories.json"
SEED = 7

DEPARTMENTS = ["Management", "Finance", "HR", "Sales", "Operations", "IT"]
MAKE_MODEL = {
    "Laptop": [("Dell", "Latitude 5540"), ("HP", "EliteBook 640"), ("Lenovo", "ThinkPad T14")],
    "Desktop": [("Dell", "OptiPlex 7010"), ("HP", "ProDesk 600")],
    "Server": [("Dell", "PowerEdge R450"), ("HPE", "ProLiant DL360")],
    "Printer": [("HP", "LaserJet M428"), ("Brother", "HL-L6400DW"), ("Kyocera", "ECOSYS M2540")],
    "Network": [("Ubiquiti", "USW-48-PoE"), ("Netgear", "GS724T"), ("HPE Aruba", "AP-515")],
    "Peripheral": [("Logitech", "C920 webcam"), ("Jabra", "Evolve2 headset"), ("Dell", "P2422H monitor")],
}


def _serial(rng: random.Random) -> str:
    return "".join(rng.choice("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789") for _ in range(10))


def build_assets() -> list[dict[str, object]]:
    """Build the synthetic asset list with explicit, documented counts."""
    rng = random.Random(SEED)
    # Explicit counts: a simulated Halden estate.
    plan = [
        ("Laptop", 45, "In use"),
        ("Desktop", 33, "In use"),
        ("Server", 6, "In use"),
        ("Printer", 8, "In use"),
        ("Network", 9, "In use"),
        ("Peripheral", 12, "In stock"),
    ]
    rows: list[dict[str, object]] = []
    tag = 0
    for asset_type, count, default_status in plan:
        for _ in range(count):
            tag += 1
            make, model = rng.choice(MAKE_MODEL[asset_type])
            dept = rng.choice(DEPARTMENTS)
            purchase = dt.date(2019, 1, 1) + dt.timedelta(days=rng.randint(0, 2500))
            warranty = purchase + dt.timedelta(days=rng.choice([1095, 1825, 2190]))
            prefix = {"Laptop": "HQ-LT", "Desktop": "HQ-WS", "Server": "HQ-SRV",
                      "Printer": "HQ-PRN", "Network": "HQ-NET", "Peripheral": "HQ-PER"}[asset_type]
            rows.append({
                "AssetTag": f"HAL-{tag:05d}",
                "Hostname": f"{prefix}-{tag:03d}",
                "Type": asset_type,
                "Manufacturer": make,
                "Model": model,
                "Department": dept,
                "AssignedTo": "" if asset_type in ("Server", "Network") else f"user{tag:03d}",
                "Location": rng.choice(["HQ - Head Office", "HQ - Server Room", "Warehouse", "In stock - IT store"]),
                "SerialNumber": _serial(rng),
                "PurchaseDate": purchase.isoformat(),
                "WarrantyEnd": warranty.isoformat(),
                "Supplier": rng.choice(["Northwind Technology (fictional)", "Contoso Hardware (fictional)", "Fabrikam Supplies (fictional)"]),
                "CostPKR": rng.choice([45000, 65000, 95000, 120000, 185000, 420000]),
                "OperatingSystem": {"Laptop": "Windows 11 Pro", "Desktop": "Windows 11 Pro",
                                    "Server": "Windows Server 2025"}.get(asset_type, ""),
                "Status": default_status,
                "Synthetic": "yes",
            })
    return rows


def _load_ticket_module():
    spec = importlib.util.spec_from_file_location("p09_seed_data", TICKET_SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


def write_csv(rows: list[dict[str, object]], path: pathlib.Path) -> None:
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    assets = build_assets()
    write_csv(assets, HERE / "halden-assets.csv")
    by_type: dict[str, int] = {}
    for row in assets:
        by_type[str(row["Type"])] = by_type.get(str(row["Type"]), 0) + 1

    seed_module = _load_ticket_module()
    categories = seed_module.load_categories(str(CATALOGUE))
    tickets = seed_module.build_tickets(150, 4, 20261002, categories)
    seed_module.write_csv(tickets, str(HERE / "halden-tickets.csv"))

    print(f"{len(assets)} synthetic assets written: {by_type}")
    print(f"{len(tickets)} synthetic tickets written (4 simulated weeks, seed 20261002)")
    print("All rows are synthetic and labelled in the Synthetic column / subject prefix.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
