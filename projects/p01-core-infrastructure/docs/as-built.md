# P1 as-built — Halden Distribution Ltd. core infrastructure

> **Status: build kit complete, lab execution pending.** This document records the *designed*
> configuration from [`00-design.md`](./00-design.md) and is written so that the *measured* facts
> can be pasted straight in. Nothing in this file is presented as a captured result: the
> **Verified** column stays empty until the matching script has actually been run in the lab and
> `10-Get-AsBuilt.ps1` has produced its output.
>
> **How to finish this document:** run `.\scripts\10-Get-AsBuilt.ps1` on DC01. It writes
> `evidence/raw/p01-as-built-facts.md` from the live system. Sanitize that output (per
> AGENTS.md 4.6) and paste it into the sections below, replacing *(designed)* with *(verified)*.
> Evidence files go in `evidence/public/` with names like `p01-ph2-replsummary-result.png`.

## 1. Environment summary

| Item | Designed value | Verified |
|---|---|---|
| Domain | `ad.halden.internal` | ☐ |
| NetBIOS name | `HALDEN` | ☐ |
| Forest / domain functional level | Windows Server 2025 | ☐ |
| Hypervisor | Hyper-V on Windows 11 Pro (HOST01) | ☐ |
| LAN | 192.168.10.0/24, private switch `Halden-LAN` | ☐ |
| Gateway | FW01 (OPNsense) 192.168.10.1 | ☐ |
| Time source | DC01 (PDC emulator) ← `time.windows.com` | ☐ |

## 2. Servers and roles

| Host | Role | OS | vCPU | RAM (start–max) | Disk | IP |
|---|---|---|---|---|---|---|
| DC01 | AD DS, DNS, DHCP (primary), PDC emulator, time source | Windows Server 2025 | 2 | 1–2 GB | 40 GB | 192.168.10.10 |
| DC02 | AD DS (GC), DNS, DHCP (failover partner) | Windows Server 2025 | 2 | 1–2 GB | 40 GB | 192.168.10.11 |
| FS01 | File services, DFS-N, FSRM, shadow copies | Windows Server 2025 | 2 | 1–2 GB | 60 GB | 192.168.10.20 |
| LNX01 | Application server, AD-joined | Ubuntu Server 24.04 | 1 | 0.5–1 GB | 20 GB | 192.168.10.30 |
| WS01 | Workstation (policy test client) | Windows 11 Enterprise eval | 2 | 2–4 GB | 64 GB | DHCP |
| WS02 | Workstation / future PAW | Windows 11 Enterprise eval | 2 | 2–4 GB | 64 GB | DHCP |

## 3. FSMO and replication *(designed)*

| Fact | Designed value | Verified |
|---|---|---|
| Schema master | DC01 | ☐ |
| Domain naming master | DC01 | ☐ |
| RID master | DC01 | ☐ |
| PDC emulator | DC01 | ☐ |
| Infrastructure master | DC01 | ☐ |
| Global catalogue | DC01, DC02 | ☐ |
| Replication health | `repadmin /replsummary` 0 fails | ☐ |
| Sites | HQ (192.168.10.0/24), WAREHOUSE (192.168.20.0/24) | ☐ |

## 4. DNS *(designed)*

| Item | Value |
|---|---|
| Forward zone | `ad.halden.internal` (AD-integrated) |
| Reverse zone | `10.168.192.in-addr.arpa` (AD-integrated) |
| Zone transfers | None — AD replication only |
| Scavenging | Enabled: no-refresh 7 days, refresh 7 days |
| Forwarders | 9.9.9.9, 1.1.1.1 |
| Conditional forwarders | None |
| Dynamic updates | Secure only; DHCP updates records as `svc-dhcpdns` |
| DC NIC DNS order | Each DC lists its peer first, itself second (never a public resolver) |

## 5. DHCP *(designed)*

| Item | Value |
|---|---|
| Servers | DC01 (primary), DC02 (failover partner) |
| Scope | `HQ-Clients` 192.168.10.100–192.168.10.200 /24, lease 8 days |
| Options | 003 `192.168.10.1` · 006 `192.168.10.10, 192.168.10.11` · 015 `ad.halden.internal` |
| Failover | `HQ-Failover`, load balance 50/50, MaxClientLeadTime 1 h, auto state transition on |
| Name protection | Enabled |
| Dynamic DNS | Enabled, with dedicated `svc-dhcpdns` credentials |
| Authorised servers | DC01, DC02 (both registered in AD) |

## 6. Directory structure

Object counts and the OU tree are produced by `10-Get-AsBuilt.ps1` (users per OU) and by the
import log (`logs/import-<date>.csv`). **Designed:** the OU tree in `00-design.md` §7, the AGDLP
groups in §12, and 85 synthetic user accounts imported from `data/halden-staff.csv`.

| Fact | Designed value | Verified |
|---|---|---|
| Users created from CSV | 85 (synthetic staff file) | ☐ |
| Role groups (`G_`) | 8 | ☐ |
| Resource groups (`DL_`) | 8 | ☐ |
| Service accounts | `svc-dhcpdns` | ☐ |
| Idempotent re-run | 85 skipped, 0 created, 0 errors | ☐ |

## 7. File services *(designed)*

| Share | Path | Access | DFS path |
|---|---|---|---|
| Finance | `C:\Shares\Finance` | `DL_Share-Finance_RW` (M), `DL_Share-Finance_RO` (RX) | `\\ad.halden.internal\Company\Finance` |
| HR | `C:\Shares\HR` | `DL_Share-HR_RW` (M), `DL_Share-HR_RO` (RX) | `\\ad.halden.internal\Company\HR` |
| Sales | `C:\Shares\Sales` | `DL_Share-Sales_RW` (M) | `\\ad.halden.internal\Company\Sales` |
| Operations | `C:\Shares\Operations` | `DL_Share-Operations_RW` (M) | `\\ad.halden.internal\Company\Operations` |
| Company | `C:\Shares\Company` | `DL_Share-Company_RO` (RX) | `\\ad.halden.internal\Company\Shared` |
| Users$ | `C:\Shares\Users$` | `DL_Share-Users_Home` (list/create) + `CREATOR OWNER` | — |

Settings: share permission `Authenticated Users: Change` (NTFS does the real control), NTFS
inheritance disabled at each share root, **Access-Based Enumeration on**, `CREATOR OWNER` on home
folders, FSRM quota template "Home 10GB Soft" on home folders, file screen "Block Executables" on
department shares, weekly large/duplicate file report, shadow copies at 07:00 and 12:00.

## 8. Group Policy *(designed)*

| GPO | Linked to | Key settings |
|---|---|---|
| `DOMAIN - Password & Lockout - v1` | Domain root | 14-char minimum, complexity on, lockout 10 attempts / 15 min |
| `WKS - Drive Maps - v1` | Workstations OU | GPP drive maps with group item-level targeting; loopback merge |
| `WKS - Security Baseline - v1` | Workstations OU | Placeholder — P4 imports the baseline |
| `WKS - Windows Update - v1` | Workstations OU | Placeholder — P5 configures update rings |
| `USR - Desktop Standards - v1` | Users OU | Secure screen saver at 600 s |
| `WKS - Kiosk Lockdown - v1` | Kiosks OU | Control Panel blocked (loopback replace) |
| `SRV - Remote Management - v1` | Servers OU | WinRM on, `IPv4Filter` 192.168.10.* (P6 narrows to MGMT) |

Central Store: `\\ad.halden.internal\SYSVOL\ad.halden.internal\Policies\PolicyDefinitions`.
Backups: `configs/gpo-backup/` (produced by `08-New-HaldenGpos.ps1`, committed once sanitized).

## 9. Linux integration *(designed)*

| Item | Value |
|---|---|
| Join method | `realmd` + `adcli` + SSSD |
| Computer object | `OU=Linux,OU=Servers,OU=Halden` |
| Login allow-list | `realm deny --all`, then `realm permit -g G_IT_LinuxAdmins` |
| Sudo | `/etc/sudoers.d/ad-admins`: `%G_IT_LinuxAdmins@ad.halden.internal ALL=(ALL) ALL` |
| SSH | `PermitRootLogin no`, `PasswordAuthentication no`, `AllowGroups g_it_linuxadmins@…`, `MaxAuthTries 3` |
| Host firewall | `ufw` deny incoming, allow 22/tcp from 192.168.10.0/24 only; `fail2ban` enabled |
| Time | `chrony` syncing to the domain hierarchy |

## 10. Known gaps and exceptions

| Item | Note |
|---|---|
| DHCP server role on domain controllers | Accepted risk in a small business; documented rather than hidden. A hardened design would move DHCP to a member server. |
| `PasswordAuthentication no` on LNX01 | AD passwords are used at the console only; SSH requires a key. This is a deliberate trade-off and is documented for interview questions. |
| TLS on internal web services | Certificates arrive with the internal CA in P6; HTTP only until then. |
| Backups | Shadow copies cover accidental deletion, not server loss. Real backups are P8. |
