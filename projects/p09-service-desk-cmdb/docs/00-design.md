# P9 — Phase 0: Design document (design before you build)

**Project:** P9 IT Service Desk, Asset Inventory (CMDB) and Documentation Hub
**Company:** Halden Distribution Ltd. (fictional, 85 users) · **Domain:** `ad.halden.internal`
**Status:** Phase 0 design complete — build kit written, lab execution pending · **Owner:** Muhammad Ibrahim Akmal · **Mode:** A (Advisor)
**Spec:** [`docs/plan/P09-service-desk-cmdb-documentation.md`](../../../docs/plan/P09-service-desk-cmdb-documentation.md)

> Why design first: an ITSM platform is a business system, not a server. The categories, the SLA
> targets, the CMDB scope and the escalation routes are decisions the business has to live with,
> and every one of them shapes the reports everyone will read later. Getting them wrong produces
> the classic failure — a helpdesk nobody picks the right category for, and an asset register
> nobody trusts. As with P1, the "why" questions in an interview are answered by this document.

---

## 1. Goal and scope

Replace email/WhatsApp support and a stale asset spreadsheet with one supportable system:

- **GLPI** on OPS01 (PHP + MariaDB) as the single service desk and CMDB, with agent-based asset
  discovery reconciled against the live network.
- A **helpdesk** with ITIL categories, priority-based SLAs, an L1 → L2 → vendor escalation matrix,
  a self-service portal and a knowledge base.
- A **service catalogue** with request forms, including a new-starter form that hands off to the
  P2 joiner/mover/leaver process.
- A **vendor, contract and licence register** with renewal alerts at 90 and 30 days.
- A **BookStack** documentation hub holding the P1–P8 as-built docs, runbooks and diagrams, with
  an owner and review date on every page.
- **Config-as-code**: a nightly export of GPO, AD, DHCP, DNS, firewall and NPS configuration to a
  private Git repository, with drift detection that flags changes with no approved change record.

Out of scope for P9: the identity automation itself (P2), endpoints and hardening (P4), the
firewall/VLAN build (P6), the SIEM (P7) and backups (P8). P9 **documents** and **serves** those
projects.

## 2. Business context (why this exists)

At Halden, support requests arrive by email, Teams, WhatsApp and by people walking up to the desk.
Nothing is tracked, so nobody knows the workload, what keeps breaking, or whether a user waits an
hour or a week. The asset spreadsheet is out of date, and the firewall support contract expired
unnoticed because no one owned the renewal. When the previous IT person left, the documentation
left with them. For a small business this is not just untidy: assets nobody tracks are assets
nobody patches, and a support function with no numbers cannot be improved or defended at budget
time.

Market evidence: many SMBs still track IT assets on spreadsheets or not at all, and outdated
records lead to overspending and to unmanaged devices sitting on the network (see
`docs/plan/00-research-and-selection.md`, finding 9); third-party involvement in breaches doubled
to 30% (Verizon DBIR 2025, finding 3), which makes knowing your vendors and contracts a security
task as well as an administrative one. CIS Controls 1 and 2 — asset and software inventory — are
the first two IG1 safeguards.

## 3. Design principles

1. **Serve the business, then the tool.** Write the catalogue, priority matrix and escalation route
   first; the software only implements decisions the business already made.
2. **Keep it simple enough to be used.** Two category levels, four priorities, one helpdesk queue
   per tier — the plans that fail are the ones with sixty categories.
3. **Automate the comparison, not the paperwork.** An asset register is only true on the day it is
   reconciled; the reconciliation runs weekly by script, not by memory.
4. **Everything as code and scripted** (`scripts/00..NN`, idempotent, logged, lab-guarded) so the
   stack is rebuildable and the scripts are themselves portfolio evidence.
5. **Config-as-code with a change hook.** A nightly diff catches the change nobody announced; the
   GLPI change record is what turns "something changed" into "an approved change changed it".
6. **Secrets never in the wiki or the repository.** Credentials live in the password manager;
   scripts read them from prompts, the environment or the git-ignored `.env`.
7. **Evidence first:** every phase defines what to capture *before* it runs (§16).

## 4. Host and stack (OPS01)

OPS01 is a single Ubuntu Server 24.04 VM (2 vCPU, 1–2 GB RAM, 40 GB disk, `192.168.10.40`) running
the whole stack with Docker Compose. It is deliberately one host for a lab of this size; the RAM is
kept inside the 16 GB lab budget by running only the VMs a phase needs.

| Container | Role | Notes |
|---|---|---|
| `halden-glpi-db` | MariaDB for GLPI | backend network, no host port |
| `halden-glpi` | GLPI 10 — ITSM + CMDB | HTTPS via reverse proxy (P6 AD CS certificate) |
| `halden-kuma` | Uptime Kuma | monitoring; **installed here for P8's backup heartbeat** (plan adjustment in `01-candidate-fit-and-tailored-roadmap.md`) |
| `halden-bookstack-db` | MariaDB for BookStack | backend network |
| `halden-bookstack` | Documentation hub | LDAP auth to AD |

The stack definition is `configs/docker-compose.yml`; credentials come only from the git-ignored
`.env` seeded from `configs/.env.example`. Until the P6 reverse proxy and certificate exist, the
UIs bind to `127.0.0.1` and are reached through the host; **the lab is never exposed to the
internet.**

## 5. Service catalogue (summary — full copy in `business/p09-service-catalogue.md`)

| Service | Request type | Approval | Target |
|---|---|---|---|
| New starter setup | Form (HR) | HR + manager | Ready the business day before the start date (P2) |
| Leaver | Form (HR) | HR | ≤ 1 hour (P2) |
| Software installation | Form | Manager (+ IT if not approved) | 2 business days |
| VPN access | Form | Manager | 1 business day (P6) |
| Shared folder access | Form | Data owner (department head) | 1 business day (P1/P6) |
| Hardware request | Form | Manager + budget holder | Quote in 3 business days |
| Incident | Portal / email / phone | — | Per the priority SLA |
| Report phishing | Form / email | — | Acknowledge in 1 hour (P7) |
| Restore a file | Form | — | Self-service immediate; request 2 business days (P8) |

The machine-readable version is `configs/glpi-service-catalogue.json`, which
`scripts/03-configure_glpi_sla.py` turns into GLPI self-service forms.

## 6. Ticket lifecycle

```
Reported (portal / email collector / phone / API)
   → Auto-categorised (business rules; Security → L2, payroll-day Finance → urgency up)
   → Owned by L1 within the TTO target (SLA clock starts)
   → Resolved & closed, or escalated:
        L1 IT Support  (password reset, printer, BitLocker recovery, software request — uses the KB)
        L2 SysAdmin     (AD/GPO, servers, network, security alerts)
        L3 Vendor / MSP (hardware warranty, ISP, firewall vendor, line-of-business app)
   → Problem record raised for recurring issues (3+ of the same fault → permanent fix)
```

Every transition is logged, so the reports can show volume, first-contact resolution and where
tickets wait longest.

## 7. Priority matrix and SLA targets

Impact × Urgency → priority; targets are **business hours** (Mon–Fri 08:00–18:00) on the
configured calendar. TTO = time to own, TTR = time to resolve.

| Priority | Impact × Urgency | Example | TTO | TTR | Escalate at |
|---|---|---|---|---|---|
| P1 Critical | High × High | Whole site down, ransomware, payroll-day failure | 15 min | 4 h | 75% of TTR |
| P2 High | High × Medium | A department cannot work, VPN down for all remote users | 1 h | 8 h | 75% of TTR |
| P3 Medium | Medium × Medium | One user cannot work, workaround exists | 4 h | 2 business days | 75% of TTR |
| P4 Low | Low × Low | Service request, cosmetic issue | 1 business day | 5 business days | 75% of TTR |

Machine-readable in `configs/glpi-sla-priorities.json`; the deadline arithmetic (including
weekend and holiday rollover) is proven by `scripts/tests/test_sla.py`.

## 8. Escalation matrix (summary — full copy in `business/p09-escalation-matrix.md`)

| Tier | Owns | Escalate to | What to include |
|---|---|---|---|
| **L1 IT Support** | Password/unlock, printers, BitLocker recovery, software requests, first-line triage | L2 after the KB steps fail or the SLA timer is near | Ticket ID, user, exact error, what the KB steps showed |
| **L2 SysAdmin** | AD/GPO, servers, network/VPN, security alerts | L3 when the issue is a vendor product or warranty | Ticket ID, timeline, logs, business impact |
| **L3 Vendor / MSP** | Hardware warranty, ISP, firewall vendor, line-of-business app | — (contract/SLA governs the response) | Ticket ID, serial/account, contract reference, agreed window |

## 9. CMDB scope and CI types

Scope: everything that is addressed, supported or licensed, plus the contracts that cover it.
Computer and server records are discovered by the **GLPI Agent** (Windows MSI via GPO, Linux
package with a systemd timer); printers and network gear are discovered by **SNMP** from one agent
in the management VLAN. Each type carries the lifecycle fields below.

| CI type | Discovered by | Lifecycle fields |
|---|---|---|
| Computer / laptop | GLPI Agent | user, department, location, purchase date, warranty end, supplier, cost, OS |
| Server | GLPI Agent | role, location, purchase date, warranty end, supplier, cost |
| Printer | SNMP | location, department, supplier, contract end |
| Network equipment | SNMP | location, firmware, supplier, contract end |
| Software licence | manual + inventory | publisher, seats owned vs installed, cost, renewal date |

Lifecycle states: **In stock → In use → In repair → Retired → Disposed**. Definitions live in
`configs/glpi-cmdb-categories.json`.

## 10. Reconciliation approach (making the CMDB true)

An asset register drifts the moment it is typed. Reconciliation compares **three sources**:

1. The CMDB itself (GLPI API or a CSV export).
2. Live **DHCP leases** (`Get-DhcpServerv4Lease` on DC01/DC02).
3. An **`nmap -sn` ping sweep** per lab subnet.

Every device is classified as **Matched**, **Unknown-OnNetwork** (on the network but not in the
CMDB — a security problem) or **Stale-InGlpi** (in the CMDB but not seen). The success criterion
is **0 unknown-on-network**, run weekly by `scripts/02-Test-AssetReconciliation.ps1`. A second
script, `scripts/05-Test-CmdbDrift.ps1`, extends the comparison to **AD computer objects, DNS A
records and DHCP reservations** so the CMDB is checked against the P1 domain itself, not just the
network.

## 11. Software and licences

A **software dictionary** normalises publisher and product names so counts are meaningful. The P5
**approved-software list** flags anything unauthorised (CIS Safeguard 2.3), and each licence record
is tied to the installs it covers so a **licence compliance / right-sizing report** can show seats
owned versus seats actually used (the IT Support Officer cost angle).

## 12. Vendors, contracts and renewals

All suppliers are **fictional**. Each supplier record carries account numbers, support numbers and
escalation contacts; each contract carries start/end, notice period, cost and auto-renew, and
triggers **alerts at 90 and 30 days** before the notice date. Contracts link to the assets they
cover, so "what breaks if we do not renew this?" is answerable. The vendor management procedure
(`business/p09-vendor-management.md`) covers how a case is raised, time-bound vendor access and an
annual review that includes security questions.

## 13. Documentation hub (BookStack)

Shelves: **Infrastructure** (AD & Identity, Servers, Network, Backup & DR, Monitoring),
**Security** (Standards, Assessments, Incident Response), **Runbooks** (Daily/Weekly/Monthly
checks, Break-fix, DR), **Policies** (P10 pack) and **Vendors** (contact sheets, no secrets).
Every page uses one template — Purpose · Scope · Owner · Last reviewed · Next review · Content ·
Related pages — and a monthly script lists pages whose review date has passed. Structure and
seed pages are in `configs/bookstack-structure.json`; `scripts/10-Seed-BookStack.sh` creates them.

## 14. Config-as-code and drift detection

`scripts/06-Export-HaldenConfigs.ps1` (Windows) and `scripts/07-export-configs.sh` (Linux and
OPNsense) export configuration nightly into the **`halden-configs`** Git repository. The secret
handling per source is written down in `configs/halden-config-sources.json`; OPNsense configs are
**filtered** before write and can additionally be encrypted with git-crypt/SOPS.

`scripts/08-Test-ConfigDrift.ps1` is the control: it lists the files changed by the last commit and
checks GLPI for an approved change record inside the comparison window. A changed file with no
matching approved change is an **unauthorised change** and, with `-Apply`, raises a High ticket.
This is the demonstrable answer to "someone changed the firewall and didn't tell anyone."

## 15. Integrations

- **P2** — the new-starter form creates a ticket that references the JML run; when the JML log shows
  the account was created, the ticket is updated and closed.
- **P7** — Wazuh High alerts become Security tickets (business rule BR-004).
- **P8** — a failed or missed restore test is caught by the Uptime Kuma backup heartbeat (a PUSH
  monitor) and opens a P2 Backup ticket (business rule BR-005).
- **P10** — the GLPI change records are the change log that config-as-code drift is checked against.

## 16. Build phases and evidence plan

| Phase | Deliverable | Evidence to capture |
|---|---|---|
| 0 | Service catalogue, priority matrix, SLA policy, escalation matrix, design doc | (the documents themselves) |
| 1 | GLPI + MariaDB, LDAP mapping, agent discovery, reconciliation, software dictionary | GLPI asset list, reconciliation CSV, unauthorised-software report |
| 2 | Categories, SLAs, business rules, email collector, forms, KB, synthetic tickets | SLA config, escalation on a ticket, KB list, new-starter form → ticket |
| 3 | Suppliers, contracts, licences, right-sizing report | 90/30-day renewal alert, licence report |
| 4 | BookStack structure + page template + review reminder | BookStack shelf/book tree, a page with owner and review date |
| 5 | Config export to Git + drift detection | Git history of configs, a drift alert for an unapproved change |

## 17. Acceptance tests (run before calling P9 Done)

| Test | Expected |
|---|---|
| Weekly reconciliation against DHCP + nmap | 0 unknown-on-network devices |
| A non-approved application installed on a client | Appears in the unauthorised-software report |
| Raise a P2 ticket and let its TTR reach 75% | The L2 group is notified and the status is Escalated |
| Submit the new-starter form | Ticket created, approval requested, task references the P2 JML run |
| Let a contract cross the 90-day notice line | A renewal alert is raised |
| Change a firewall rule with no change record | Next morning's drift check raises an unauthorised-change High ticket |
| Re-run `scripts/00-Prepare-OPS01.sh` and the seed scripts | Idempotent: no duplicates, no errors |
| Restore the service-desk database from the nightly dump | GLPI and BookStack come back with data intact |

## 18. Snapshot and rollback plan

- **Before every phase:** take a hypervisor snapshot of OPS01 (and any host the phase touches),
  named `snap-p9-ph<N>-before`; record the rollback note for the phase. OPS01 is not a domain
  controller, so snapshot reverts are safe.
- **Stack rollback:** `docker compose down` stops the stack without deleting volumes; restoring a
  volume from the P9 nightly dump (`scripts/09-Backup-ServiceDeskDb.sh`) recovers GLPI/BookStack
  data.
- **Config-as-code rollback:** a bad config change is reverted in Git; re-applying an old config is
  itself a change and needs a change record.
- Phase 0 changed nothing in the lab, so no snapshot was needed. **Phase 1 does change things.**

## 19. Decisions and assumptions

1. One host (OPS01) runs the whole stack, matching `LAB-INVENTORY.md`; a production design might
   separate the database and the web tier.
2. GLPI **10** is the target (GLPI 11 native forms are preferred when available; Formcreator on
   10). Record the version chosen in `DECISIONS.md` when the lab build starts.
3. SMTP for the email collector: the M365 trial mailbox from P2 while it lasts, otherwise a small
   lab mail server. Decide at Phase 2 and record it.
4. Uptime Kuma is installed here (not in P7) because P8's backup heartbeat depends on it — the
   roadmap adjustment in `docs/plan/01-candidate-fit-and-tailored-roadmap.md`.
5. All ticket, asset, supplier and contract data used in the simulation is **synthetic**.

## 20. Risks

| Risk | Mitigation |
|---|---|
| Too many categories make reports useless | Two levels maximum; categories fixed in `configs/glpi-cmdb-categories.json` |
| SLAs that ignore business hours or cannot be met | Business-hours calendar configured; targets proven by unit tests |
| Docs go stale without owners | Owner + review date on every page; monthly review reminder |
| Secrets in the wiki or Git | Password manager only; OPNsense export filtered/encrypted; secret scan in CI |
| Asset register drifts from reality | Weekly reconciliation script; 0 unknown-on-network target |
| First GLPI/BookStack install leaves default accounts | Hardening steps in the deploy script and the bring-up runbook |

## 21. Interview notes (Phase 0)

**"How do you support an L1 team?"** Good knowledge-base articles, a clear escalation matrix with a
handoff template, and a habit of turning recurring escalations into either a KB article or a
permanent fix (problem management). The escalation matrix in P9 names exactly what to include when
handing a ticket to L2, so nothing gets bounced back for missing information.

**"How do you keep documentation current?"** Owners and review dates on every page, a monthly
reminder that lists overdue pages, docs updated as part of the change process, and configuration
exported automatically every night so the as-built is never more than a day old.

**"Someone changed the firewall and didn't tell anyone."** The nightly config export and the
drift check catch it the next morning: the diff shows the changed file, the GLPI change records
show no approved change for that date, and an "unauthorised change" High ticket is raised. That is
why config-as-code and change management are one control, not two.

---

*Next step: Phase 0 business documents (already drafted in `business/`), then Phase 1 — snapshot
OPS01, edit the git-ignored `.env`, and run `scripts/00-Prepare-OPS01.sh` (Mode A: the owner runs
the commands and pastes output back).*
