# Halden Distribution Ltd. — Service levels: recovery objectives agreed with the business

| Field | Value |
|---|---|
| **Document ID** | SLA-REC-001 |
| **Version** | 0.9 (draft for approval) |
| **Owner** | IT Lead |
| **Approver** | Managing Director — **signature pending** |
| **Date agreed** | *(on approval)* |
| **Review date** | 12 months after approval, or after any drill |

> **These are targets, not results.** No recovery has been measured yet. Every "objective" figure below
> is what the business has asked for; the achieved figures are recorded only after a timed drill and
> appear in `p08-dr-drill-report.md`. Halden Distribution Ltd. is fictional; the targets are part of a
> home-lab portfolio project.

---

## 1. Definitions

| Term | Plain meaning |
|---|---|
| **Recovery Time Objective (RTO)** | How long a system may be down before the business is seriously hurt |
| **Recovery Point Objective (RPO)** | How much data we may lose, expressed in time ("the last hour of work") |
| **Maximum Tolerable Downtime (MTD)** | The absolute limit beyond which the impact is unacceptable; the RTO must sit inside it |

## 2. Agreed objectives by tier

| Tier | Systems | RTO | RPO | MTD | Backup frequency | Retention |
|---|---|---|---|---|---|---|
| 0 — Foundation | DC01/DC02 (AD, DNS, DHCP), FW01 config | 2 hours | 24 hours | 1 day | Daily VM + daily system state | 30 daily, 12 monthly |
| 1 — Critical | FS01 Finance/Sales, LNX01 order system + database | 4 hours | 1 hour | 2 days | Hourly file + nightly VM | 24 hourly, 14 daily, 8 weekly, 12 monthly |
| 2 — Important | OPS01 (GLPI/BookStack), SIEM01 (Wazuh) | 24 hours | 24 hours | 5 days | Nightly | 14 daily, 8 weekly |
| 3 — Deferrable | Workstations (no local data by policy) | 3 days | Not applicable (re-imaged) | 10 days | Re-image from standard build | — |

## 3. The cost/risk trade-off the business is accepting

| Choice | Cost implication | Effect |
|---|---|---|
| RPO of **1 hour** for Tier 1 | Hourly backups: more storage, more load, more monitoring | At most one hour of file and order data is lost |
| RPO of **24 hours** for Tier 0 | Daily backups | Up to a day of directory changes, mostly recovered from the second controller |
| 30-day immutable retention | Storage that cannot be reclaimed early | An attacker cannot destroy the last month of recovery points |
| Off-site, encrypted copy | A recurring storage cost for the off-site location | A fire, theft or flood does not destroy every copy |

Tighter objectives cost more. The tiers above are the balance the business has accepted; they can be
changed, but only deliberately and with the cost understood.

## 4. What IT commits to

1. Backing up every in-scope system at the frequency above, and monitoring that it happened.
2. Keeping at least one copy that **cannot be deleted** within its retention period.
3. **Testing restores every week** and reporting the result.
4. Running a **full recovery drill** at least twice a year and reporting the measured times.
5. Telling the business **honestly** when a target was missed, and what will change as a result.

## 5. What the business commits to

1. **Signing off** these objectives and reviewing them annually.
2. Storing work in the managed location (network shares), not on a local desktop, so it is covered.
3. Reporting suspected data loss promptly rather than attempting recovery alone.

## 6. Measurement and reporting

| Measure | Source | Frequency | Reported to |
|---|---|---|---|
| Restore test success rate | automated weekly restore test | Monthly | Management (P10 monthly report) |
| Recovery time vs target | timed recovery drill | Twice yearly | Management |
| Data loss vs target | timed recovery drill | Twice yearly | Management |
| Backup job failures | backup monitoring | Daily (operational) / Monthly (summary) | IT operations / Management |

## 7. Measured performance

| Measure | Target | Latest measured | Date measured |
|---|---|---|---|
| Restore test success rate | *(to be set after the first drill)* | **not measured** | — |
| Recovery time — Tier 0 | 2 hours | **not measured** | — |
| Recovery time — Tier 1 | 4 hours | **not measured** | — |
| Data loss — Tier 1 | 1 hour | **not measured** | — |

> This table is deliberately empty. It will be filled from real drill output, and it will show misses
> as well as successes.

---

## Approval

| Role | Name | Signature | Date |
|---|---|---|---|
| IT Lead | Muhammad Ibrahim Akmal |  |  |
| Managing Director (business owner) |  |  |  |
| Finance (cost acceptance) |  |  |  |

> **Unsigned draft** for the fictional company Halden Distribution Ltd.
