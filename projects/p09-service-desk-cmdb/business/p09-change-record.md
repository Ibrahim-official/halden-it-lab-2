# Halden Distribution Ltd. — change record: P9 service desk, CMDB and documentation hub

> Retroactive change record, written to the standard Halden uses for every change (it feeds the
> change log and the P10 governance dashboard). In a small company the same person often proposes
> and approves; that separation is documented honestly rather than pretended. Halden Distribution
> Ltd. is the fictional company used in this portfolio.

| Field | Value |
|---|---|
| **Change ID** | CHG-2026-003 |
| **Title** | P9 — Deploy GLPI ITSM/CMDB, Uptime Kuma, BookStack and config-as-code drift detection |
| **Raised by** | IT (Muhammad Ibrahim Akmal) |
| **Approved by** | Managing Director *(business owner of the fictional Halden; see note on the lab)* |
| **Date raised** | 2026-10-02 |
| **Planned implementation** | 2026-10-02 onwards, phase by phase (Phase 0 → Phase 5) |
| **Category / risk** | IT service management — Medium risk (new business system; no Tier 0 outage expected) |
| **Affected services** | Support request handling, asset records, documentation, monitoring, nightly configuration export |
| **Affected systems** | OPS01 (new container stack), DC01/DC02 (discovery and config export sources), FS01, WS01, FW01 |

## 1. Description of the change

Introduce a single IT service management platform for Halden: **GLPI** (with MariaDB) as the service
desk and CMDB on OPS01, with an L1 → L2 → vendor escalation model, priority-based SLAs on a business
calendar, a self-service catalogue with forms, a knowledge base, and agent-based asset discovery
reconciled against DHCP and the network. Add a **vendor, contract and licence register** with renewal
alerts. Add **BookStack** as the documentation hub for the as-built docs, runbooks and diagrams of
P1–P8, with an owner and review date on every page. Add **Uptime Kuma** for monitoring, including the
backup heartbeat the recovery project (P8) depends on. Finally, export GPO, AD, DHCP, DNS, firewall
and NPS configuration to a private Git repository nightly, with **drift detection** that flags a
changed file with no approved change record.

## 2. Reason for the change

Support requests currently arrive by email, Teams, WhatsApp and in person, so nothing is tracked and
nobody can say what keeps breaking or how long users wait. Asset records are held in an out-of-date
spreadsheet, and the firewall support contract expired unnoticed. Documentation exists only in one
person's head. This change gives the business a tracked, measurable support function, an asset
register that is reconciled weekly, a home for documentation that outlives any individual, and a
control (config-as-code plus change records) that catches unannounced configuration changes.

## 3. Impact and risk

| Area | Impact | Mitigation |
|---|---|---|
| Staff | A new, single place to raise requests; email and phone still work | One-page "how to raise a ticket" guide; desk briefed before the change |
| Support handling | During cutover, tickets could be missed | Run the old channels in parallel until the desk is proven; monitor the queue daily for the first week |
| Asset records | An automated inventory could overwrite or duplicate records | Agent discovery imported into a staged view before being accepted into the CMDB; reconciliation reviewed before records change |
| Configuration exports | Raw exports can contain secrets | DHCP leases excluded, NPS shared secret excluded, OPNsense config filtered (or git-crypt/SOPS); secret scan before commit |
| New service on one host | OPS01 is a single point of failure for the desk | Nightly database backups with a restore runbook; P8 adds the offsite copy; the host is snapshotted before each phase |

## 4. Implementation plan (phases)

| Phase | Work | Window | Verification |
|---|---|---|---|
| 0 | Service catalogue, priority matrix, SLA policy, escalation matrix, vendor procedure | Same day | Reviewed against `docs/plan/P09-…` |
| 1 | GLPI + MariaDB, LDAP mapping, agent discovery, reconciliation, software dictionary | Out of hours | Reconciliation report produced; unauthorised-software report produced |
| 2 | Categories, SLAs, business rules, email collector, forms, knowledge base, synthetic tickets | Out of hours | A test ticket escalates at 75% TTR; a form creates a ticket |
| 3 | Suppliers, contracts, licences, right-sizing report | Out of hours | A renewal alert fires at the 90-day line |
| 4 | BookStack structure, page template, review reminder | Out of hours | Shelf/book tree present; a page shows owner and review date |
| 5 | Config export to Git, commit + alert, drift detection | Out of hours | Git history exists; an unapproved change raises a High ticket |

## 5. Test plan (acceptance)

1. Weekly reconciliation against DHCP + `nmap` — **0 unknown-on-network devices**.
2. Install a non-approved application on a client — it appears in the unauthorised-software report.
3. Raise a P2 ticket and let its TTR reach 75% — L2 is notified and the ticket is Escalated.
4. Submit the new-starter form — a ticket is created, approval requested, and the task references the
   P2 joiner process.
5. Let a contract cross the 90-day notice line — a renewal alert fires.
6. Change a firewall rule with no change record — the next drift check raises an unauthorised-change
   High ticket.
7. Re-run the preparation and seed scripts — idempotent, no duplicates, no errors.
8. Restore the service-desk database from the nightly dump — GLPI and BookStack recover with data
   intact.

## 6. Backout plan

OPS01 is snapshotted before each phase (`snap-p9-ph<N>-before`); backout is to revert that snapshot
and stop the affected containers. `docker compose down` stops the stack without deleting data
volumes. A bad configuration change is reverted in Git, and re-applying an old configuration is
itself a change requiring a change record. Restoring the database is covered by
`docs/runbooks/restore-service-desk-database.md`. Because OPS01 is not a domain controller, snapshot
reverts are low risk.

## 7. Post-implementation review

To be completed when the last phase is verified: actual completion date, acceptance test results,
anything that went wrong, and whether any phase overran. Results are recorded in
`projects/p09-service-desk-cmdb/README.md` with a source file for every number.

> Note: this is a home-lab change record for a fictional company (Halden Distribution Ltd.). The
> technical content, scripts and test results are real; the business approval line represents the lab
> owner's decision, not a real customer sign-off. The **approval and signature are deliberately
> unsigned** until the review happens.
