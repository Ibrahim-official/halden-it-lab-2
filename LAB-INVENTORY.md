# Lab inventory (no passwords here)

> **Mode A (Advisor) is active — Mode B has not been granted.** Nothing in this table is reachable
> by an agent yet. The values are the **planned/designed** lab from
> `projects/p01-core-infrastructure/docs/00-design.md` (D10/D11 in `DECISIONS.md`); the
> **Built?** column is ticked only after the host has actually been created and verified.

| Host | Role | OS | VLAN | IP | Project | vCPU | RAM (start–max) | Disk | Built? |
|---|---|---|---|---|---|---|---|---|---|
| HOST01 | Hypervisor (Hyper-V on Windows 11 Pro) | Windows 11 Pro | — | 192.168.10.5 (mgmt) | P1+ | — | 16 GB host | — | ☐ |
| FW01 | HQ firewall, VPN endpoint, DHCP relay | OPNsense | trunk | 192.168.10.1 | P1, P6 | 1 | 0.5–1 GB | 8 GB | ☐ |
| DC01 | Domain controller, DNS, DHCP (primary), PDC emulator | Windows Server 2025 | 10 SERVERS | 192.168.10.10 | P1+ | 2 | 1–2 GB | 40 GB | ☐ |
| DC02 | Domain controller, DNS, DHCP (failover partner) | Windows Server 2025 | 10 SERVERS | 192.168.10.11 | P1+ | 2 | 1–2 GB | 40 GB | ☐ |
| FS01 | File services (DFS-N, FSRM, VSS); NPS role in P6 | Windows Server 2025 | 10 SERVERS | 192.168.10.20 | P1, P2, P6 | 2 | 1–2 GB | 60 GB | ☐ |
| LNX01 | Linux app server (AD-joined); scanner in P5 | Ubuntu Server 24.04 | 10 SERVERS | 192.168.10.30 | P1, P5, P7 | 1 | 0.5–1 GB | 20 GB | ☐ |
| OPS01 | GLPI, Uptime Kuma, BookStack (containers) | Ubuntu Server 24.04 | 10 SERVERS | 192.168.10.40 | P9, P8 heartbeat, P7 | 2 | 1–2 GB | 40 GB | ☐ |
| SIEM01 | Wazuh manager + indexer + dashboard | Ubuntu Server 24.04 | 10 SERVERS | 192.168.10.41 | P7 | 2–4 | 4–6 GB (only while in use) | 60 GB | ☐ |
| BKP01 | Backup repository (PBS / restic / MinIO); **not domain-joined** | Ubuntu Server 24.04 | 10 → 40 MGMT (P6) | 192.168.10.42 | P8 | 2 | 1–2 GB | 40 GB + backup disk | ☐ |
| CA01 | Internal enterprise CA (AD CS) | Windows Server 2025 | 10 SERVERS | 192.168.10.43 | P6 | 2 | 1–2 GB | 40 GB | ☐ |
| WS01 | User workstation (policy/compliance test client) | Windows 11 Enterprise eval | 10 → 30 USERS-HQ (P6) | DHCP | P1+ | 2 | 2–4 GB | 64 GB | ☐ |
| WS02 | Admin workstation / Tier 0 PAW | Windows 11 Enterprise eval | 10 → 40 MGMT (P6) | DHCP | P3, P4, P6 | 2 | 2–4 GB | 64 GB | ☐ |
| FW02 | Warehouse firewall (site 2) | OPNsense | 20 WAREHOUSE | 192.168.20.1 | P6 | 1 | 0.5–1 GB | 8 GB | ☐ |

**Only 6 VMs exist in P1** (FW01, DC01, DC02, FS01, LNX01, WS01). WS02 is added in P3, OPS01 in
P9, SIEM01 in P7, BKP01 in P8, CA01 and FW02 in P6. Run only the VMs a phase needs — that is what
keeps the whole lab inside 16 GB.

**Domain:** `ad.halden.internal` · **NetBIOS:** HALDEN · **Functional level:** Windows Server 2025
**Lab marker file on Linux hosts:** `/etc/halden-lab` (scripts refuse to run without it)
**Guard for Windows scripts:** `(Get-ADDomain).DNSRoot -eq 'ad.halden.internal'`

## Network zones (target, after P6)

| VLAN | Zone | Subnet | DHCP |
|---|---|---|---|
| 10 | SERVERS | 192.168.10.0/24 | Static |
| 20 | WAREHOUSE (site 2) | 192.168.20.0/24 | Windows DHCP via relay |
| 30 | USERS-HQ | 192.168.30.0/24 | Windows DHCP via relay |
| 40 | MGMT | 192.168.40.0/24 | Static |
| 50 | GUEST | 192.168.50.0/24 | OPNsense (internet only) |
| 60 | IOT | 192.168.60.0/24 | OPNsense |
| — | VPN-USERS | 192.168.70.0/24 | VPN pool |

**In P1 the lab is flat**: everything sits in 192.168.10.0/24 on the private switch `Halden-LAN`.
The VLANs above are the target for P6 and are recorded here so the design is visible from the start.

## Software and licences

| Software | Where | Licence | Expiry tracked in |
|---|---|---|---|
| Windows Server 2025 eval | DC01, DC02, FS01, CA01 | Evaluation (180 days) | `PROGRESS.md` |
| Windows 11 Enterprise eval | WS01, WS02 | Evaluation (90 days) | `PROGRESS.md` |
| Microsoft 365 Business Premium trial | Cloud identity (P2) | 30-day trial — **start only at P2 Phase 3** | `PROGRESS.md` |
| OPNsense, Ubuntu, GLPI, Wazuh, PingCastle, BloodHound CE, restic, PBS, WireGuard | Various | Free / open source | — |

Credentials live in the owner's password manager, never in this repository.
