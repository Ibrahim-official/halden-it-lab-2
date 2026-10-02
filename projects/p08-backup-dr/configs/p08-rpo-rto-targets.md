# P8 RPO/RTO targets — Halden Distribution Ltd.
# Where it applies: agreed with the business during the BIA (Phase 0) and used as the acceptance
# thresholds for the DR drill (Phase 5). These are TARGETS. Actual recovery times and data loss are
# recorded only after a timed drill has been run, in business/p08-dr-drill-report.md and README.md.
# Source of the design: docs/00-design.md §4 and §6.

## Terms (in plain language)

- **RTO (Recovery Time Objective)** — how long the system may be *down* before the business is
  seriously hurt. "Back in service within X."
- **RPO (Recovery Point Objective)** — how much *data* the business can afford to lose, measured in
  time. "We may lose the last Y of work."
- **MTD (Maximum Tolerable Downtime)** — the absolute limit after which the impact is unacceptable;
  RTO must sit inside the MTD.

## Targets by tier

| Tier | Systems | RTO target | RPO target | MTD | Backup frequency | Retention |
|---|---|---|---|---|---|---|
| 0 — Foundation | DC01/DC02 (AD, DNS, DHCP), FW01 config | 2 hours | 24 hours | 1 day | daily VM + daily system state | 30 daily, 12 monthly |
| 1 — Critical | FS01 Finance/Sales, LNX01 order app + DB | 4 hours | 1 hour | 2 days | hourly file incremental + nightly VM | 14 daily, 8 weekly, 12 monthly |
| 2 — Important | OPS01 (GLPI/BookStack), SIEM01 (Wazuh) | 24 hours | 24 hours | 5 days | nightly | 14 daily, 8 weekly |
| 3 — Deferrable | Workstations (no local data; redirects) | 3 days | n/a (re-image) | 10 days | re-image from standard build | — |

## Why these numbers

- **AD at 24 h RPO** because AD changes are rare and multi-master replication means losing one DC's
  day of changes is mostly recovered from the surviving DC. The *RTO* of 2 h is what matters: without
  identity, nothing else can be restored.
- **Tier 1 at 1 h RPO** because invoices, orders and the order database change continuously; a day of
  lost orders cannot be re-entered without cost to the business.
- **Tier 2 at 24 h** because losing a day of helpdesk tickets or SIEM logs is annoying, not existential.
- **Tier 3 re-image** because there is no local data by policy (folder redirection), so there is
  nothing to back up — this is a policy decision, not a technical convenience.

## Agreed with the business

| Field | Value |
|---|---|
| Approved by (business) | Managing Director *(fictional Halden; the lab owner)* |
| Approved by (IT) | IT Lead |
| Date agreed | *(to be completed at the BIA sign-off)* |
| Review date | annually, or after any drill that breaches a target |
| Cost/risk note | tighter RPO means more frequent backups, more storage and more cost; the tiers above are the trade-off the business accepted |

## How these become results

1. The weekly restore test measures **restore duration** per VM and **hash-match** for files.
2. The Phase 5 drill measures **time to full recovery** per system with a stopwatch.
3. Actual values are compared with the targets above; any breach becomes an action with an owner.
4. Only then are the numbers published. Until then, every row in `README.md` reads "not measured".
