#!/usr/bin/env python3
"""Generate the SYNTHETIC asset-criticality inventory for the P5 prioritizer.

**This data is synthetic.** It describes invented hosts belonging to the fictional company
Halden Distribution Ltd. (see LAB-INVENTORY.md). It is not a scan result, not real customer data
and not a real organisation. It exists so the prioritizer and the static browser demo are
reproducible offline; the live program feeds the same schema from the P9 asset CMDB.

The rows are derived in format from the P1 lab hosts: host, role, exposure, criticality and owner.

Usage:
    python3 gen_asset_inventory.py [--out asset-criticality.csv]
"""
from __future__ import annotations

import argparse
import csv
from pathlib import Path

# host, role, os, exposure, criticality, owner, zone, notes
ASSETS: list[tuple[str, str, str, str, int, str, str, str]] = [
    ("FW01", "HQ firewall, VPN endpoint and DHCP relay", "OPNsense", "internet", 3, "IT", "edge",
     "Compromise here is a perimeter breach; firmware is a vendor-advisory item"),
    ("DC01", "Domain controller, DNS, DHCP primary, PDC emulator", "Windows Server 2025", "internal", 3, "IT", "servers",
     "Tier 0: authentication and name resolution for the whole company"),
    ("DC02", "Domain controller, DNS, DHCP failover partner", "Windows Server 2025", "internal", 3, "IT", "servers",
     "Tier 0: keeps logons working if DC01 is down"),
    ("FS01", "File server (DFS-N, FSRM, shadow copies)", "Windows Server 2025", "internal", 3, "IT", "servers",
     "Departmental and home data"),
    ("LNX01", "Linux application server and vulnerability scanner", "Ubuntu Server 24.04", "internet", 2, "IT", "servers",
     "Publishes the internal app; infection here can reach the servers"),
    ("WS01", "User workstation (policy and compliance test client)", "Windows 11 Enterprise", "internal", 1, "Sales", "users",
     "Supports one user; rebuildable from the image"),
    ("WS02", "Admin workstation (Tier 0 PAW)", "Windows 11 Enterprise", "internal", 2, "IT", "users",
     "Privileged access workstation from P3"),
    ("OPS01", "Tools host (GLPI, BookStack, Uptime Kuma)", "Ubuntu Server 24.04", "internal", 1, "IT", "servers",
     "Service desk and documentation; no business data of its own"),
    ("SIEM01", "Security monitoring (Wazuh manager and indexer)", "Ubuntu Server 24.04", "internal", 2, "IT", "servers",
     "Detection and log retention"),
    ("BKP01", "Backup repository", "Ubuntu Server 24.04", "internal", 3, "IT", "servers",
     "Last line of defence; never domain-joined"),
]

FIELDS = ("host", "role", "os", "exposure", "criticality", "owner", "zone", "notes")


def generate(out: Path) -> int:
    """Write the synthetic asset inventory CSV and return the row count."""
    with out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(FIELDS)
        writer.writerows(ASSETS)
    return len(ASSETS)


def main() -> int:
    """CLI entry point."""
    parser = argparse.ArgumentParser(description="Generate the synthetic Halden asset inventory (P5).")
    parser.add_argument(
        "--out",
        type=Path,
        default=Path(__file__).resolve().parent / "asset-criticality.csv",
        help="output CSV path",
    )
    args = parser.parse_args()
    count = generate(args.out)
    print(f"{count} synthetic assets written to {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
