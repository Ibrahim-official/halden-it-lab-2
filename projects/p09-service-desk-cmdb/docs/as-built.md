# P9 as-built — Halden Distribution Ltd. service desk, CMDB and documentation hub

> **Status: build kit complete, lab execution pending.** This document records the *designed*
> configuration from [`00-design.md`](./00-design.md) and is written so that the *measured* facts
> can be pasted straight in. Nothing here is presented as a captured result: the **Verified**
> column stays empty until the matching script has actually been run in the lab.
>
> **How to finish this document:** run the phase scripts on OPS01 (and the discovery scripts from a
> management host), collect their real output, sanitize it per AGENTS.md 4.6, and paste it into the
> tables below, replacing *(designed)* with *(verified)*. Evidence files go in `../evidence/public/`
> with names like `p09-ph1-reconciliation-result.csv` and `p09-ph2-sla-config-result.png`.

## 1. Environment summary

| Item | Designed value | Verified |
|---|---|---|
| Host | OPS01 (Ubuntu Server 24.04, 2 vCPU, 1–2 GB RAM, 40 GB) | ☐ |
| IP / VLAN | `192.168.10.40` · VLAN 10 SERVERS | ☐ |
| Runtime | Docker Engine + Compose plugin | ☐ |
| Stack directory | `/opt/halden` | ☐ |
| Secrets | git-ignored `/opt/halden/.env`; values also in the password manager | ☐ |
| Public exposure | none — UIs bound to `127.0.0.1` until the P6 reverse proxy | ☐ |

## 2. Containers

| Container | Image (planned) | Role | Verified |
|---|---|---|---|
| `halden-glpi-db` | `mariadb:11` | GLPI database (backend network only) | ☐ |
| `halden-glpi` | `glpi/glpi:10` | GLPI 10 — ITSM + CMDB | ☐ |
| `halden-kuma` | `louislam/uptime-kuma:1` | Uptime Kuma — monitoring + P8 backup heartbeat | ☐ |
| `halden-bookstack-db` | `mariadb:11` | BookStack database (backend network only) | ☐ |
| `halden-bookstack` | `lscr.io/linuxserver/bookstack` | Documentation hub | ☐ |

## 3. GLPI authentication and hardening *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Authentication | LDAP/LDAPS (636) to `ad.halden.internal` | ☐ |
| Group mapping | `G_IT_ServiceDesk` → Technician, `G_IT_SysAdmin` → Technician, everyone → Self-Service | ☐ |
| Default accounts | Removed or changed: `glpi`, `tech`, `normal`, `post-only` | ☐ |
| Installer | `install/install.php` deleted after setup | ☐ |
| API | Application token + user token, stored in `.env` / password manager | ☐ |
| HTTPS | Reverse proxy with a certificate from the P6 AD CS (`glpi.halden.internal`) | ☐ |

## 4. Service catalogue, SLA and business rules *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Services in the catalogue | 9 (see `configs/glpi-service-catalogue.json`) | ☐ |
| Priorities | P1 Critical, P2 High, P3 Medium, P4 Low | ☐ |
| Business calendar | Mon–Fri 08:00–18:00 `Asia/Karachi`, with configured holidays | ☐ |
| TTO / TTR (P1) | 15 min / 4 h | ☐ |
| TTO / TTR (P2) | 1 h / 8 h | ☐ |
| TTO / TTR (P3) | 4 h / 2 business days | ☐ |
| TTO / TTR (P4) | 1 business day / 5 business days | ☐ |
| Escalation point | Notify the L2 group at 75% of TTR | ☐ |
| Business rules | 5 (BR-001 … BR-005 in `configs/glpi-sla-priorities.json`) | ☐ |
| Groups | `L1-ServiceDesk`, `L2-SysAdmin`, `L3-Vendors` | ☐ |

## 5. CMDB and discovery *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| CI types | Computer, Server, Printer, Network equipment, Phone/peripheral, Software licence | ☐ |
| Lifecycle states | In stock → In use → In repair → Retired → Disposed | ☐ |
| Windows discovery | GLPI Agent MSI via GPO startup script, `RUNNOW=1`, `TAG=HQ` | ☐ |
| Linux discovery | GLPI Agent package + systemd timer | ☐ |
| Network discovery | SNMP tasks (OPNsense, printers) from one agent in the management VLAN | ☐ |
| Reconciliation sources | GLPI API/CSV + `Get-DhcpServerv4Lease` + `nmap -sn` | ☐ |
| Reconciliation target | 0 unknown-on-network | ☐ |
| Drift comparison | AD computers + DNS A records + DHCP reservations vs CMDB | ☐ |
| Software | Dictionary normalised; unauthorised software flagged (CIS 2.3) | ☐ |
| Synthetic asset inventory | 113 assets in `../data/halden-assets.csv` (synthetic) | ☐ |

## 6. Vendors, contracts and licences *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Suppliers | ISP, firewall vendor, hardware vendor, M365 reseller, offsite backup provider, MSP/IR retainer, printer lease (all fictional) | ☐ |
| Contracts | start/end, notice period, cost, auto-renew | ☐ |
| Renewal alerts | 90 and 30 days before the notice date | ☐ |
| Licences | seats owned vs installed; right-sizing report | ☐ |

## 7. Documentation hub (BookStack) *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Shelves | Infrastructure, Security, Runbooks, Policies, Vendors | ☐ |
| Page template | Purpose · Scope · Owner · Last reviewed · Next review · Content · Related pages | ☐ |
| Review reminder | Monthly script lists pages whose review date has passed | ☐ |
| Authentication | LDAP to AD | ☐ |
| Secrets | none stored in the wiki; password manager only | ☐ |

## 8. Config-as-code and drift detection *(designed)*

| Source | Export | Secret handling | Verified |
|---|---|---|---|
| GPO | `Backup-GPO -All` + `Get-GPOReport -All -ReportType Xml` | none required | ☐ |
| AD structure | OUs, groups, privileged-group membership to CSV/JSON | none required | ☐ |
| DHCP | `Export-DhcpServer -File dhcp.xml -Leases:$false` | leases excluded | ☐ |
| DNS | `Export-DnsServerZone` / zone files | none required | ☐ |
| NPS | `netsh nps export … exportPSK=NO` | shared secret excluded | ☐ |
| OPNsense | `/conf/config.xml` via SSH | filtered, and optionally git-crypt/SOPS | ☐ |
| Linux | sshd/sudoers/ufw/package versions | no private keys copied | ☐ |

Commit message `nightly: <date>`; a non-empty diff posts an alert. Drift check: a changed file with
no approved change record raises an unauthorised-change High ticket.

## 9. Uptime Kuma monitors *(designed)*

| Monitor | Type | Target | Verified |
|---|---|---|---|
| DC01 LDAP/LDAPS | TCP | `dc01.ad.halden.internal:636` | ☐ |
| DC02 LDAP/LDAPS | TCP | `dc02.ad.halden.internal:636` | ☐ |
| FS01 SMB | TCP | `fs01.ad.halden.internal:445` | ☐ |
| GLPI HTTPS | HTTP | `https://glpi.halden.internal` | ☐ |
| BookStack HTTPS | HTTP | `https://bookstack.halden.internal` | ☐ |
| FW01 admin | HTTP | `https://192.168.10.1` | ☐ |
| Backup heartbeat (P8) | Push | pinged by the P8 restore test; missed ping → P2 Backup ticket | ☐ |

## 10. Known gaps and exceptions

| Item | Note |
|---|---|
| Single host for the whole stack | Accepted for a lab of this size; a production design would separate the database tier. |
| GLPI 10 vs 11 | GLPI 11 forms are preferred when available; on GLPI 10 the Formcreator plugin is used. Version recorded in `DECISIONS.md` at build time. |
| Email collector during the M365 trial window | The trial mailbox from P2 is used while it lasts; if it expires, a small lab mail server is used. Decide and record at Phase 2. |
| HTTPS until P6 | The internal CA and certificates arrive with P6; until then the UIs are HTTP on `127.0.0.1` only. |
| Synthetic data | Tickets, assets, suppliers and contracts are invented for the fictional company and labelled synthetic. |

> Nothing in this document has been measured yet. The **Verified** column is the single place where
> real lab output is pasted, and it is filled only after the matching phase has actually run.
