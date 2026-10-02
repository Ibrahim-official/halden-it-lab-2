#!/usr/bin/env python3
"""Generate the SYNTHETIC scanner export and KEV/EPSS cache used by the P5 project.

**This data is synthetic.** It is not a real scan of any network. It exists so that:

* the prioritizer (``scripts/05-prioritize.py``) can be demonstrated and unit-tested offline;
* the static browser demo (``demo/index.html``) has a rich, well-formed sample to run on.

The CVE identifiers are real, publicly documented identifiers, but the **hosts, the finding
placement, the EPSS probabilities and the KEV flags are invented** to exercise every tier of the
model. Real KEV/EPSS values are fetched from the public feeds by
``scripts/05-prioritize.py fetch-feeds``; this file deliberately uses a small synthetic stand-in
so the sample run needs no internet access. Nothing here is a claim about the Halden lab.

The output is deterministic (seeded), so the row counts quoted in ``data/README.md`` are reproducible.

Usage:
    python3 gen_sample_findings.py [--findings sample-scanner-export.csv] [--enrichment sample-enrichment.json]
"""
from __future__ import annotations

import argparse
import csv
import json
import random
from pathlib import Path

# --- Vulnerability catalogue ------------------------------------------------------------------
# key -> (cve, cvss, service, port, title, solution)
CATALOGUE: dict[str, tuple[str, float, str, int, str, str]] = {
    "log4shell": (
        "CVE-2021-44228", 10.0, "http", 8080,
        "Apache Log4j2 JNDI remote code execution (Log4Shell)",
        "Upgrade log4j-core to 2.17.1 or later and restart the application.",
    ),
    "activemq": (
        "CVE-2023-46604", 10.0, "activemq", 61616,
        "Apache ActiveMQ OpenWire remote code execution",
        "Upgrade ActiveMQ to 5.18.3 or later.",
    ),
    "eternalblue": (
        "CVE-2017-0144", 8.1, "smb", 445,
        "Microsoft SMBv1 remote code execution (EternalBlue)",
        "Disable SMBv1 and apply security update MS17-010.",
    ),
    "zerologon": (
        "CVE-2020-1472", 10.0, "netlogon", 0,
        "Netlogon elevation of privilege (Zerologon)",
        "Apply the August 2020 update and enforce secure channel.",
    ),
    "bluekeep": (
        "CVE-2019-0708", 9.8, "rdp", 3389,
        "Remote Desktop Services remote code execution (BlueKeep)",
        "Apply the RDP security update and require Network Level Authentication.",
    ),
    "outlook": (
        "CVE-2023-23397", 9.8, "outlook", 0,
        "Microsoft Outlook privilege elevation via calendar reminder",
        "Apply the March 2023 update and block outbound SMB from workstations.",
    ),
    "win_tcpip": (
        "CVE-2024-38063", 9.8, "ipv6", 0,
        "Windows TCP/IP IPv6 remote code execution",
        "Apply the August 2024 cumulative update.",
    ),
    "follina": (
        "CVE-2022-30190", 7.8, "msdt", 0,
        "Windows Support Diagnostic Tool remote code execution (Follina)",
        "Apply the June 2022 update and disable the MSDT URL protocol.",
    ),
    "clfs": (
        "CVE-2022-37969", 7.8, "clfs", 0,
        "Windows Common Log File System driver elevation of privilege",
        "Apply the September 2022 cumulative update.",
    ),
    "afd": (
        "CVE-2023-21768", 7.8, "afd", 0,
        "Windows Ancillary Function Driver for WinSock elevation of privilege",
        "Apply the January 2023 cumulative update.",
    ),
    "openssh_agent": (
        "CVE-2023-38408", 9.8, "ssh", 22,
        "OpenSSH ssh-agent PKCS#11 remote code execution",
        "Upgrade OpenSSH and disable SSH agent forwarding.",
    ),
    "regresshion": (
        "CVE-2024-6387", 8.1, "ssh", 22,
        "OpenSSH unauthenticated remote code execution (regreSSHion)",
        "Upgrade OpenSSH to 9.8p1 or later.",
    ),
    "glibc": (
        "CVE-2023-4911", 7.8, "glibc", 0,
        "glibc ld.so buffer overflow (Looney Tunables)",
        "Upgrade the distribution glibc package.",
    ),
    "openssl": (
        "CVE-2022-0778", 7.5, "openssl", 443,
        "OpenSSL BN_mod_sqrt infinite loop (denial of service)",
        "Upgrade OpenSSL to 1.1.1n or 3.0.2 or later.",
    ),
    "sweet32": (
        "CVE-2016-2183", 7.5, "tls", 443,
        "TLS/SSL weak cipher suite (SWEET32, 3DES)",
        "Disable 3DES cipher suites and reissue the certificate.",
    ),
    "ssh_enum": (
        "CVE-2018-15473", 5.3, "ssh", 22,
        "OpenSSH username enumeration",
        "Upgrade OpenSSH to 7.7 or later.",
    ),
    "frr": (
        "CVE-2023-38802", 7.5, "frr", 179,
        "FRRouting BGP daemon denial of service",
        "Upgrade the OPNsense FRR plugin to the fixed release.",
    ),
    # Findings that are not tied to a single CVE (config weaknesses and outdated software)
    "weak_tls": (
        "", 5.9, "tls", 443,
        "Weak SSL/TLS cipher suites accepted (RC4/3DES)",
        "Disable RC4 and 3DES cipher suites; prefer TLS 1.2 or 1.3.",
    ),
    "fw_firmware": (
        "", 0.0, "http", 443,
        "OPNsense firmware is out of date: vendor security advisories not applied",
        "Back up the configuration, then update FW01 to the current OPNsense release.",
    ),
    "smb_signing": (
        "", 5.3, "smb", 445,
        "SMB signing is not required (relay and tampering risk)",
        "Require SMB signing by Group Policy on servers and workstations.",
    ),
    "defender_stale": (
        "", 0.0, "windows-defender", 0,
        "Microsoft Defender definitions are out of date",
        "Update definitions and confirm the WSUS/policy update path.",
    ),
    "restic_outdated": (
        "", 0.0, "ssh", 22,
        "Backup software version is out of date (upstream bug fixes not applied)",
        "Upgrade restic/MinIO to the current release in the maintenance window.",
    ),
}

# --- Per-host finding lists (catalogue keys; repeats are intentional duplicates) ---------------
HOST_FINDINGS: dict[str, list[str]] = {
    "FW01": ["frr", "weak_tls", "fw_firmware"],
    "DC01": ["zerologon", "win_tcpip", "follina", "sweet32", "smb_signing"],
    "DC02": ["zerologon", "win_tcpip", "follina", "sweet32", "smb_signing"],
    "FS01": ["eternalblue", "win_tcpip", "follina", "sweet32", "smb_signing"],
    "LNX01": [
        "log4shell", "activemq", "openssh_agent", "regresshion", "glibc", "openssl", "ssh_enum",
        "log4shell", "openssh_agent",  # duplicates a scanner may report twice; the tool deduplicates
    ],
    "WS01": ["eternalblue", "follina", "clfs", "sweet32", "defender_stale"],
    "WS02": ["bluekeep", "outlook", "win_tcpip", "afd", "sweet32", "smb_signing"],
    "OPS01": ["glibc", "openssl", "ssh_enum", "weak_tls"],
    "SIEM01": ["openssh_agent", "glibc", "openssl", "ssh_enum"],
    "BKP01": ["glibc", "regresshion", "openssl", "ssh_enum", "restic_outdated"],
}

# --- Synthetic KEV + EPSS stand-in (NOT the live feeds) ----------------------------------------
# kev = appears in CISA KEV; ransomware = KEV entry linked to a known ransomware campaign.
ENRICHMENT: dict[str, tuple[bool, bool, float]] = {
    "CVE-2021-44228": (True, True, 0.97),    # Log4Shell
    "CVE-2023-46604": (True, True, 0.62),    # ActiveMQ
    "CVE-2020-1472": (True, True, 0.90),     # Zerologon
    "CVE-2017-0144": (True, True, 0.94),     # EternalBlue
    "CVE-2019-0708": (True, False, 0.72),    # BlueKeep
    "CVE-2023-23397": (True, False, 0.80),   # Outlook
    "CVE-2024-38063": (False, False, 0.55),  # Windows TCP/IP IPv6
    "CVE-2022-30190": (False, False, 0.30),  # Follina
    "CVE-2022-37969": (False, False, 0.25),  # CLFS
    "CVE-2023-21768": (False, False, 0.20),  # AFD
    "CVE-2023-38408": (False, False, 0.55),  # OpenSSH agent
    "CVE-2024-6387": (False, False, 0.42),   # regreSSHion
    "CVE-2023-4911": (False, False, 0.35),   # Looney Tunables
    "CVE-2022-0778": (False, False, 0.08),   # OpenSSL
    "CVE-2016-2183": (False, False, 0.05),   # SWEET32
    "CVE-2018-15473": (False, False, 0.02),  # OpenSSH enumeration
    "CVE-2023-38802": (False, False, 0.09),  # FRR
}

FINDING_FIELDS = ("cve", "cvss", "host", "service", "port", "title", "solution", "first_seen")


def generate(findings_out: Path, enrichment_out: Path, seed: int = 7) -> tuple[int, int]:
    """Write the synthetic sample and enrichment files. Returns (finding rows, CVE entries)."""
    rng = random.Random(seed)
    rows: list[list[object]] = []
    for host, keys in HOST_FINDINGS.items():
        for key in keys:
            cve, cvss, service, port, title, solution = CATALOGUE[key]
            # Older dates for the lower-severity batches so the SLA snapshot shows some ageing.
            first_seen = f"2026-{rng.randint(8, 9):02d}-{rng.randint(1, 28):02d}"
            rows.append([cve, f"{cvss:.1f}", host, service, port, title, solution, first_seen])

    findings_out.parent.mkdir(parents=True, exist_ok=True)
    with findings_out.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.writer(handle)
        writer.writerow(FINDING_FIELDS)
        writer.writerows(rows)

    enrichment = {
        "schema": "p05-kev-epss-sample/1",
        "synthetic": True,
        "note": (
            "Synthetic KEV/EPSS stand-in for the offline sample. Real values come from the CISA KEV "
            "catalogue and the FIRST EPSS API via scripts/05-prioritize.py fetch-feeds."
        ),
        "cves": {
            cve: {"kev": kev, "ransomware": ransomware, "epss": epss}
            for cve, (kev, ransomware, epss) in sorted(ENRICHMENT.items())
        },
    }
    enrichment_out.parent.mkdir(parents=True, exist_ok=True)
    enrichment_out.write_text(json.dumps(enrichment, indent=2) + "\n", encoding="utf-8")
    return len(rows), len(enrichment["cves"])


def main() -> int:
    """CLI entry point."""
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description="Generate the synthetic P5 scanner sample (not a real scan).")
    parser.add_argument("--findings", type=Path, default=here / "sample-scanner-export.csv")
    parser.add_argument("--enrichment", type=Path, default=here / "sample-enrichment.json")
    parser.add_argument("--seed", type=int, default=7)
    args = parser.parse_args()
    finding_rows, cve_entries = generate(args.findings, args.enrichment, args.seed)
    print(f"{finding_rows} synthetic finding rows and {cve_entries} CVE enrichment entries written")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
