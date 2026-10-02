# P8 as-built — Halden Distribution Ltd. backup, recovery and DR

> **Status: build kit complete, lab execution pending.** This document records the *designed*
> configuration from [`00-design.md`](./00-design.md) and is written so that the *measured* facts can
> be pasted straight in. Nothing in this file is presented as a captured result: the **Verified**
> column stays empty (☐) until the matching script has actually been run in the lab.
>
> **How to finish this document:** run the numbered scripts in `../scripts/` on the target hosts, save
> the raw output under `evidence/raw/`, sanitize it (AGENTS.md 4.6) into `evidence/public/`, then
> replace the designed value in the relevant row with the measured value and tick the box. Every row
> in `README.md`'s results table starts as "not measured" for the same reason.

## 1. Environment summary

| Item | Designed value | Verified |
|---|---|---|
| Backup server | BKP01, Ubuntu Server 24.04, `192.168.10.42` | ☐ |
| VLAN | SERVERS 192.168.10.0/24 in P1 → MGMT VLAN 40 after P6 | ☐ |
| Domain-joined | **No** — local credentials only | ☐ |
| Repository | restic repository on BKP01 (`/srv/backup/restic`) | ☐ |
| Immutable copy | MinIO S3 Object Lock, COMPLIANCE, default 30 d | ☐ |
| Offline copy | encrypted USB, rotated monthly, stored off-site | ☐ |
| Sandbox for restore tests | VLAN 99, no uplink | ☐ |
| Hypervisor | Hyper-V on Windows 11 Pro (HOST01, 16 GB) | ☐ |

## 2. Platform and jobs *(designed)*

| Job | Tier | Source | Destination | Schedule | Tool |
|---|---|---|---|---|---|
| VM-level backup | 0–2 | DC01/DC02/FS01/LNX01/OPS01/SIEM01 | BKP01 | nightly | `02-Backup-HyperVVMs.ps1` |
| File-level (Tier 1) | 1 | FS01 shares, LNX01 app+DB | BKP01 → MinIO | hourly incremental; nightly VM | `restic backup` |
| File-level (Tier 2) | 2 | OPS01, SIEM01 | BKP01 → MinIO | nightly | `restic backup` |
| AD system state | 0 | DC01/DC02 | BKP01 | daily | `wbadmin start systemstatebackup` |
| Offsite copy | 0–2 | BKP01 repository | MinIO S3 | after each backup | `restic copy` |
| Offline export | 0–2 | BKP01 repository | encrypted USB | monthly | manual + rotation log |
| Prune / GC | — | BKP01 | — | daily | `restic forget --prune` |
| Verify | — | BKP01 | — | weekly | `restic check` |
| Restore test | — | BKP01 / sandbox | — | weekly | `06-Test-BackupRestore.sh` |

## 3. Retention policy *(designed)*

| Scope | Hourly | Daily | Weekly | Monthly | Immutable floor |
|---|---|---|---|---|---|
| Tier 0 Foundation | — | 30 | — | 12 | 30 d (Object Lock) |
| Tier 1 Critical | 24 | 14 | 8 | 12 | 30 d (Object Lock) |
| Tier 2 Important | — | 14 | 4 | — | 30 d (Object Lock) |
| Tier 3 Deferrable | n/a — re-image from standard build | | | | — |

Machine-readable form: `configs/p08-backup-jobs.yaml`. Narrative form: `configs/p08-retention-policy.md`.

## 4. Encryption and key escrow *(designed)*

| Item | Value | Verified |
|---|---|---|
| Repository encryption | client-side (restic passphrase never sent to storage) | ☐ |
| Passphrase source | `/etc/halden-lab/backup.env` (uncommitted) + `RESTIC_PASSWORD_FILE` | ☐ |
| Escrow | owner password manager **and** sealed printed copy stored with the offline USB | ☐ |
| Object store keys | MinIO keys in the uncommitted env file; never in Git | ☐ |
| Key rotation | change-managed: re-init repository + full backup | ☐ |

## 5. Immutability *(designed — the proof is a failed delete)*

| Test | Designed result | Measured | Verified |
|---|---|---|---|
| `mc rm --recursive --force <bucket>/fs01` | adds delete markers only | — | ☐ |
| `mc rm --recursive --force --versions <bucket>/fs01` | **refused** (WORM protected) | — | ☐ |
| `mc retention clear` (COMPLIANCE) | **refused**, even for root | — | ☐ |
| shorten retention in COMPLIANCE | **refused** | — | ☐ |
| recover via `mc cp --recursive --rewind 1h` | repository intact, `restic snapshots` lists it | — | ☐ |

## 6. Restore verification *(designed)*

| Item | Designed value | Measured | Verified |
|---|---|---|---|
| Files restored and hash-compared per week | 20 random files | — | ☐ |
| Repository integrity | `restic check --read-data-subset=5%` | — | ☐ |
| VM boot test | one VM/week, rotating DC → FS01 → LNX01 | — | ☐ |
| Service health check | DC: NTDS/DNS/Netlogon · FS01: shares · LNX01: app port | — | ☐ |
| Report | `reports/restore-test-<date>.json` + HTML | — | ☐ |
| Heartbeat | push to Uptime Kuma (up = pass) | — | ☐ |
| History target | 12 consecutive weekly results | — | ☐ |

## 7. AD recovery *(designed)*

| Procedure | When | Evidence |
|---|---|---|
| AD Recycle Bin restore | deleted object, online | restored OU and children; `Get-ADObject` |
| Authoritative restore | bulk/older mistake | DSRM + `wbadmin start systemstaterecovery` + `ntdsutil`; replication verified |
| Forest recovery (tabletop + partial) | worst case | timed steps in the sandbox; krbtgt reset twice |

Tombstone lifetime (180 days) is checked before any DC restore. A restored DC is scanned in the
sandbox before it is promoted to the production network.

## 8. DR drill results *(designed — filled in only after a timed drill)*

| System | RTO target | Actual | RPO target | Actual data loss | Pass? | Notes / fix |
|---|---|---|---|---|---|---|
| DC01 (AD/DNS/DHCP) | 2 h | not measured | 24 h | not measured | ☐ | |
| FS01 (Finance/Sales) | 4 h | not measured | 1 h | not measured | ☐ | |
| LNX01 (order app + DB) | 4 h | not measured | 1 h | not measured | ☐ | |
| OPS01 (GLPI/BookStack) | 24 h | not measured | 24 h | not measured | ☐ | |
| SIEM01 (Wazuh) | 24 h | not measured | 24 h | not measured | ☐ | |
| Workstations (re-image) | 3 days | not measured | n/a | not measured | ☐ | |
| **Full recovery to service** | **as agreed per tier** | **not measured** | | | ☐ | |

> A first drill that finds problems is a **successful** drill. The "what broke" column is the most
> valuable output, and each issue becomes an action with an owner and a date.

## 9. Known gaps and exceptions *(honest)*

| Item | Note |
|---|---|
| MinIO simulates the offsite provider | It is a separate VM/disk but shares the same physical host and power. Only the offline USB is genuinely independent. |
| Scale | Lab data is tens of GB, so dedup ratios, throughput and storage cost are illustrative, not representative. |
| No UPS | A host power loss can interrupt a backup; a backup is trusted only after a restore test. |
| RTO/RPO are targets | Actuals are pasted in only after the timed drill. Until then every results row says "not measured". |
| Copy 1 prune is irreversible | There is no "undo" for a repository prune; immutability protects Copy 2 and the USB is the fallback for Copy 1. |
