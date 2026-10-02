# P9: IT Service Desk, Asset Inventory (CMDB) and Documentation Hub

> **Pitch:** Replaced email/WhatsApp support and a stale asset spreadsheet with a single ITSM platform (GLPI): agent-based automatic asset discovery reconciled to 100% accuracy, a helpdesk with SLAs, categories, an L1→L2→vendor escalation matrix and a knowledge base, and a vendor/contract/licence register with renewal alerts. Also built a BookStack documentation hub and **config-as-code drift detection** that versions every GPO, firewall, DHCP and DNS config in Git nightly.

**Anchor score:** 90 (merged with #26 IPAM, #40 docs wiki, #41 vendor register, #42 config-as-code, #44 helpdesk) · **Time:** about 1.5 weeks · **Depends on:** P1–P8 (documents and inventories what they built)

---

## 1. Business problem

At Halden, support requests arrive by email, Teams, WhatsApp and people walking up to the desk. Nothing is tracked, so nobody knows the workload, what keeps breaking, or whether users wait an hour or a week. The asset spreadsheet is 40% wrong. The firewall support contract expired unnoticed. When the previous IT person left, the documentation left with them.

**Market evidence:** many SMBs still track IT assets manually or not at all, and outdated records lead to overspending and to unmanaged devices sitting on the network (ITSM.tools, SMB ITAM surveys). Third-party involvement in breaches doubled to 30% (Verizon DBIR 2025), which makes knowing your vendors and contracts a security task too. CIS Controls 1 and 2 (asset and software inventory) are the first two IG1 controls.

## 2. JD coverage

| Ad | Bullet proven |
|---|---|
| SysAdmin | **Maintain accurate infrastructure inventory, configurations, diagrams, and technical documentation** |
| SysAdmin | **Coordinate with vendors and service providers** |
| SysAdmin | **Provide technical support and escalation assistance to the IT Support team** |
| SysAdmin | Follow change-control procedures (drift detection) |
| Officer | **Maintain accurate records and ensure timely completion** (SLAs); coordinate with teams and follow up; process improvement; reports |

## 3. Success criteria

- [ ] **100% of lab devices** discovered automatically by the GLPI Agent; reconciliation report shows 0 unknown devices (compared with DHCP leases + nmap)
- [ ] Software inventory per device; **unauthorized software** report (CIS 2.3)
- [ ] Helpdesk: categories, priorities, **SLA (TTO/TTR)**, email-to-ticket, self-service portal, **escalation matrix**, 10+ KB articles
- [ ] **Service catalogue** with request forms (new starter → hooks into P2 JML, VPN access → P6)
- [ ] Vendor, contract and licence register with **renewal alerts at 90/30 days**
- [ ] BookStack documentation hub: as-built docs, runbooks, diagrams from P1–P8, with an owner and review date on every page
- [ ] **Nightly config backup to Git with drift alerts:** unapproved changes detected and matched against change records (P10)

## 4. Architecture

```
 OPS01 (Ubuntu 24.04, docker compose)
 ├─ GLPI 10/11 + MariaDB ─── GLPI Agent on Windows/Linux (inventory every 24h)
 │    ├─ Assets: computers, network gear, software, licences
 │    ├─ Helpdesk: tickets, SLAs, email collector, self-service, KB, problems, changes (P10)
 │    └─ Management: suppliers, contracts (renewal alerts), budgets, documents
 ├─ BookStack (docs hub)  ─── Shelves: Infrastructure | Security | Runbooks | Policies | Vendors
 ├─ (optional) NetBox (IPAM / VLAN / rack source of truth)
 └─ config-backup (cron/Task Scheduler) → Git repo "halden-configs" → diff → Wazuh/Teams alert
```

## 5. Tools and cost

[GLPI](https://glpi-project.org) + [GLPI Agent](https://github.com/glpi-project/glpi-agent) · [BookStack](https://www.bookstackapp.com) · optional [NetBox](https://netbox.dev) · Git (Gitea on OPS01 or a private GitHub repo) · PowerShell/bash · draw.io. **Cost: free.**

## 6. Step-by-step action plan

### Phase 0: Define the service (Day 1)
IT Support Officer work first:
1. **Service catalogue** (`business/p9-service-catalogue.md`): what IT offers, who can request it, approvals, target times.

   | Service | Request type | Approval | Target |
   |---|---|---|---|
   | New starter setup | Form (HR) | HR + Manager | Ready day −1 (P2 SLA) |
   | Leaver | Form (HR) | HR | ≤1 h (P2) |
   | Software install | Form | Manager (+IT if not on approved list) | 2 business days |
   | VPN access | Form | Manager | 1 business day (P6) |
   | Shared folder access | Form | **Data owner** (dept head) | 1 business day |
   | Hardware request | Form | Manager + budget holder | Quote in 3 days |
   | Incident (something broken) | Portal / email / phone | — | per priority SLA |

2. **Priority matrix** (Impact × Urgency) and **SLAs**:

   | Priority | Example | Time to own (TTO) | Time to resolve (TTR) |
   |---|---|---|---|
   | P1 Critical | Whole site down, ransomware, payroll day failure | 15 min | 4 h |
   | P2 High | Department can't work, VPN down for all remote users | 1 h | 8 h |
   | P3 Medium | One user can't work, workaround exists | 4 h | 2 business days |
   | P4 Low | Request, cosmetic issue | 1 business day | 5 business days |

3. **Escalation matrix** (`business/p9-escalation-matrix.md`): **L1 IT Support** (password resets, printer, BitLocker recovery, software requests; uses the KB) → **L2 SysAdmin** (AD/GPO, servers, network, security alerts) → **L3 Vendor/MSP** (hardware warranty, ISP, firewall vendor, line-of-business app vendor). For each: when to escalate, what information to include (template), contact channel, and response commitments.

### Phase 1: Deploy GLPI and asset discovery (Day 2–3)
1. Docker compose on OPS01 (GLPI + MariaDB, persistent volumes, HTTPS via a reverse proxy with a cert from the P6 AD CS). Remove the default accounts (`glpi`, `tech`, `normal`, `post-only`) or change their passwords, and delete `install/install.php`. **LDAP authentication to AD** (LDAPS 636) with group mapping: `G_IT_Staff` → Technician profile, everyone else → Self-Service.
2. **GLPI Agent** deployment:
   - Windows: MSI via GPO startup script, `SERVER=https://glpi.halden.internal/front/inventory.php RUNNOW=1 EXECMODE=service TAG=HQ`
   - Linux: package install, `server = https://glpi.halden.internal/`, systemd timer
   - Enable **network discovery/inventory** tasks (SNMP for OPNsense, printers) from one agent in the MGMT VLAN
3. **Reconciliation** (`scripts/Test-AssetReconciliation.ps1`): pull DHCP leases (`Get-DhcpServerv4Lease` for all scopes) + an `nmap -sn` sweep per VLAN + the GLPI API list of computers → output: in GLPI but not on the network (retired/lost?), **on the network but not in GLPI (unknown device, a security issue)**, and matched. Goal: **0 unknown**. Run it weekly.
4. **Asset lifecycle fields:** status (In stock / In use / In repair / Retired / Disposed), user, department, location, purchase date, warranty end, supplier, cost. Import the P4 Win11 readiness data as well, so warranty and Windows 11 eligibility sit side by side.
5. **Software:** set up the **dictionary** (normalise names/publishers), flag **unauthorized software** with an approved-software list, and produce a report (CIS Safeguard 2.3). Tie licences to installs (compliance count).

### Phase 2: Helpdesk configuration (Day 4–5)
1. **ITIL categories** (2 levels max): Access & Accounts · Hardware · Software · Network & VPN · Email & M365 · Printing · Security (report phishing etc.) · Requests.
2. **SLAs** from Phase 0, with business hours calendar (Mon–Fri 08:00–18:00) + **escalation levels** (notify the L2 group when 75% of TTR is used).
3. **Groups:** `L1-ServiceDesk`, `L2-SysAdmin`, `L3-Vendors` (supplier-linked). **Business rules** for auto-assignment: category Security → L2 + priority High, requester in Finance on payroll day → urgency up.
4. **Email collector:** a mailbox (M365 trial or a local mail server in the lab) → tickets. Notification templates in plain English.
5. **Self-service portal and forms:** GLPI 11 native forms (or the Formcreator plugin on GLPI 10) for each catalogue item. **New-starter form → ticket → approval → task for IT** that references the P2 JML run. Close the loop: once the JML log shows the account was created, the ticket is updated.
6. **Integrations:** P7 Wazuh High alerts and P8 failed restore tests create tickets automatically (GLPI API or email), so every alert gets an owner.
7. **Knowledge base:** write 10+ articles for L1: password reset/unlock (with identity verification), BitLocker recovery (P4), VPN setup (P6), MFA re-registration (P2), mapped drives missing, printer add, report a phishing email, restore a file from Previous Versions (P1), request software, new-starter checklist. Each has symptoms → steps → escalation criteria.
8. **Seed and simulate:** generate ~150 realistic tickets over 4 simulated weeks (script via the GLPI API, clearly labelled synthetic) so the reports have data. Process a sample by hand properly, including an escalation to a "vendor".

### Phase 3: Vendors, contracts and licences (Day 6)
1. **Suppliers:** ISP, firewall vendor/reseller, hardware vendor, M365 reseller, backup offsite provider, MSP/IR retainer, printer lease company (all fictional). Record account numbers, support numbers, SLAs and escalation contacts.
2. **Contracts:** start/end dates, notice period, cost, auto-renew, and **alerts at 90 and 30 days** before notice. Link each contract to the assets it covers.
3. **Licences:** M365 seats vs active users (cross-check with P2 stale accounts; unused licence = money), Windows Server, antivirus, etc. Produce a **licence compliance/right-sizing report** (IT Support Officer cost angle).
4. **Vendor management procedure** (`business/p9-vendor-management.md`): how to raise and track a vendor case (ticket linked to supplier), vendor access to systems (time-bound, MFA, logged), annual vendor review including security questions (this addresses the third-party breach trend).

### Phase 4: Documentation hub (Day 7–8)
1. BookStack with LDAP auth. Structure:
   ```
   Shelf: Infrastructure  → Books: AD & Identity | Servers | Network | Backup & DR | Monitoring
   Shelf: Security        → Books: Standards | Assessments | Incident Response
   Shelf: Runbooks        → Books: Daily/Weekly/Monthly checks | Break-fix | DR
   Shelf: Policies        → (P10 policy pack)
   Shelf: Vendors         → (contact sheets; secrets NOT stored here)
   ```
2. Move all P1–P8 docs in, using **one page template**: Purpose · Scope · Owner · Last reviewed · Next review · Content · Related pages. Add a **review reminder** (a monthly script lists pages whose review date has passed).
3. **Diagrams:** final set in draw.io (embedded + source file): logical L3 (P6), physical/lab host, AD sites & services, backup data flow (P8), monitoring data flow (P7), identity flow (P2).
4. **Operational checklists** (the "run" part of the job):
   - *Daily:* backup job status, Wazuh High alerts, Uptime Kuma, ticket queue
   - *Weekly:* restore-test result, patch compliance, asset reconciliation, AD health (`dcdiag`, `repadmin`)
   - *Monthly:* PingCastle, vulnerability dashboard, stale accounts, licence usage, doc reviews, KPI report (P10)
   - *Quarterly:* access reviews (P2), firewall rule review (P6), DR test (P8), vendor/contract review
5. **Secrets stay out of the wiki.** Document that they live in a password manager (e.g. Vaultwarden/Bitwarden in the lab) with shared collections per team.

### Phase 5: Config-as-code and drift detection (Day 9–10)
`scripts/Export-HaldenConfigs.ps1` + `export-configs.sh`, run nightly, committing to the `halden-configs` repo:
| Source | Export |
|---|---|
| GPOs | `Backup-GPO -All` + `Get-GPOReport -All -ReportType Xml` (XML diffs are readable) |
| AD structure | OUs, groups + membership of privileged groups, delegations → CSV/JSON |
| DHCP | `Export-DhcpServer -File dhcp.xml -Leases:$false` |
| DNS | `Export-DnsServerZone` / zone files for AD zones |
| OPNsense | `/conf/config.xml` via SSH/API (**secrets filtered or repo encrypted with git-crypt/SOPS**) |
| NPS | `netsh nps export ... exportPSK=NO` |
| Linux | `/etc/ssh/sshd_config.d`, `/etc/sudoers.d`, `ufw status`, key package versions |

- Commit with a message like `nightly: <date>`. If `git diff --stat` is non-empty, **send a Teams/Wazuh alert listing changed files**.
- **Drift check:** a changed file with no matching approved change record in GLPI (P10) for that date raises an "**unauthorized change**" High ticket. Demo it by changing a firewall rule without a change record and show the alert.
- Commit history becomes an audit trail and a rollback source (P8 DR uses the firewall config from Git).

## 7. Business layer (IT Support Officer)

| Artifact | Purpose |
|---|---|
| `business/p9-service-catalogue.md` + SLA table | What IT provides and how fast |
| `business/p9-escalation-matrix.md` | L1/L2/L3 routes and handoff template |
| `business/p9-service-desk-report.pdf` | From the 4 simulated weeks: volume by category, SLA compliance %, **first-contact resolution**, top 5 recurring issues → **problem records and fixes** (process improvement) |
| `business/p9-asset-licence-report.xlsx` | Asset status, warranty expiring, unauthorized software, licence waste (cost) |
| `business/p9-contract-renewals.xlsx` | Next 12 months of renewals with recommended actions |

## 8. Evidence to capture

GLPI asset list with agent inventory · reconciliation report (0 unknown) · unauthorized software report · SLA configuration + ticket escalation · KB list · new-starter form → ticket → JML link · contract renewal alert · BookStack structure · diagram set · Git history of configs + drift alert for an unapproved change.

## 9. Common pitfalls

- Too many ticket categories. Nobody picks the right one, and the reports become useless.
- SLAs that ignore business hours or can't be met (they destroy trust).
- Docs without an owner or review date go stale within months.
- Storing passwords in the wiki, or committing firewall configs with secrets to Git.
- An asset register nobody reconciles. Automate the comparison.

## 10. Resume bullets (templates)

- Deployed **GLPI ITSM** with agent-based discovery for **N assets** (100% reconciled against DHCP/network scans), software inventory with unauthorized-software reporting, and a vendor/contract/licence register with renewal alerts that identified **PKR X of unused licences**.
- Built a helpdesk with a **service catalogue, priority-based SLAs, L1→L2→vendor escalation matrix and 10+ KB articles**. In a 4-week simulation, first-contact resolution was **X%** and SLA compliance **Y%**.
- Implemented **config-as-code**: nightly export of GPO, DHCP, DNS, firewall and NPS configs to Git, with **drift detection** that flags changes lacking an approved change record.

## 11. Interview talking points

- **"How do you support an L1 team?"** Good KB articles, a clear escalation matrix with a handoff template, and turning recurring escalations into KB articles or permanent fixes (problem management).
- **"How do you keep documentation current?"** Owners and review dates, reminders, docs updated as part of the change process, and configs exported automatically.
- **"Someone changed the firewall and didn't tell anyone."** Nightly diff plus a change-record check catches it the next morning. Show the demo.

## 12. AI-ready build prompt

```text
Act as a senior IT service manager and sysadmin mentoring me through a homelab capstone.
Project: P9 IT Service Desk, Asset Inventory (CMDB) & Documentation Hub, fictional "Halden Distribution Ltd" (85 staff).
Lab: OPS01 Ubuntu 24.04 with docker; ad.halden.internal (LDAPS available, AD CS from P6); VLANs from P6;
Wazuh (P7), Uptime Kuma, JML automation (P2), backups (P8).

Phase by phase:
0. Service catalogue, Impact x Urgency priority matrix, SLAs (TTO/TTR), L1/L2/L3 escalation matrix with handoff template.
1. GLPI (docker compose, HTTPS, LDAP group mapping, secure defaults), GLPI Agent deployment via GPO and on Linux,
   network discovery, asset lifecycle fields, reconciliation script (DHCP leases + nmap + GLPI API),
   software dictionary + unauthorized software report.
2. Helpdesk: categories, SLAs with calendar and escalation, groups and business rules, email collector,
   forms for the catalogue (new starter linked to JML), Wazuh/backup alert -> ticket integration,
   10 KB articles (give me drafts), synthetic ticket generator via the GLPI API.
3. Suppliers, contracts with renewal alerts, licences and a right-sizing report, vendor management procedure.
4. BookStack structure, page template with owner/review date, diagram list, daily/weekly/monthly/quarterly checklists.
5. Export-HaldenConfigs (GPO, AD, DHCP, DNS, OPNsense, NPS, Linux) to Git with secret handling, nightly diff alert,
   and drift detection against approved change records.
Each phase: steps/commands, expected output, verification, screenshots. Finish with README, service desk
report outline, and resume bullets with my numbers. Start with Phase 0.
```
