# Halden Distribution Ltd. — KPI and reporting definitions

**Purpose:** define exactly what the service desk reports, how each measure is calculated, where the
data comes from, who owns it and how often — so a number in a report means the same thing to
everyone.
**Owner:** IT (Muhammad Ibrahim Akmal) · **Approver:** Managing Director · **Review:** annually
**Status of the values:** none of these measures has been captured yet. The table below says
**what will be measured and how**; it deliberately contains **no performance figures**. Actual
results are added only from a real run (see `../docs/as-built.md`).

> Halden Distribution Ltd. is the fictional company used in this portfolio.

## 1. Reporting principles

1. **A measure without a definition and a source is not used.** Each row below names the source.
2. **Business hours only** for anything time-based, on the configured Mon–Fri 08:00–18:00 calendar.
3. **No number is published that has not been measured.** Where data does not exist yet, the report
   says "not measured", not an estimate dressed as a fact.
4. **Synthetic data is labelled.** Until the system runs on real tickets, any demonstration report
   uses the synthetic dataset and says so on the page.

## 2. Service desk KPIs

| KPI | Definition (how it is calculated) | Source | Frequency | Owner |
|---|---|---|---|---|
| Ticket volume | Count of tickets created in the period, grouped by ITIL category | GLPI reports | Monthly | IT Support |
| SLA compliance — TTO | % of tickets owned within the priority's Time To Own target | GLPI SLA report vs `configs/glpi-sla-priorities.json` | Monthly | IT Support |
| SLA compliance — TTR | % of tickets resolved within the priority's Time To Resolve target | GLPI SLA report | Monthly | IT Support |
| First-contact resolution (FCR) | % of tickets resolved on the first contact with no escalation and no reopen | GLPI (resolution on first assignment, no reopen) | Monthly | IT Support |
| Reopen rate | % of closed tickets reopened within 7 days | GLPI ticket history | Monthly | IT Support |
| Backlog | Open tickets at period end, by priority and age | GLPI | Weekly | IT Support |
| Top recurring issues | The 5 most frequent categories/subjects in the period | GLPI category report | Monthly | IT Support |

## 3. Asset and CMDB KPIs

| KPI | Definition | Source | Frequency | Owner |
|---|---|---|---|---|
| Asset count by type | CI records per CI type, by lifecycle state | GLPI assets | Monthly | IT / Systems |
| Reconciliation result | Count of Matched / Unknown-OnNetwork / Stale-InGlpi | `scripts/02-Test-AssetReconciliation.ps1` CSV | Weekly | IT / Systems |
| Unknown-on-network devices | Devices seen on the network with no CMDB record (target 0) | same reconciliation CSV | Weekly | IT / Systems |
| CMDB drift | Missing-InCmdb / Orphan-InCmdb / DnsWithoutHost / Reserved-NotLeased | `scripts/05-Test-CmdbDrift.ps1` CSV | Weekly | IT / Systems |
| Unauthorised software | Installed titles not on the P5 approved list (CIS 2.3) | GLPI software report | Monthly | IT / Systems |
| Warranty expiring | Assets whose warranty ends within 90 days | GLPI asset report | Monthly | IT Support |
| Unauthorised config changes | Changed config files with no approved change record | `scripts/08-Test-ConfigDrift.ps1` CSV | Daily | IT / Systems |

## 4. Vendor, contract and licence KPIs

| KPI | Definition | Source | Frequency | Owner |
|---|---|---|---|---|
| Renewals due | Contracts reaching their 90/30-day notice line, with recommended action | GLPI contracts | Monthly | IT Support |
| Licence utilisation | Seats installed versus seats owned, per licence | GLPI licences + inventory | Monthly | IT Support |
| Licence waste | Seats owned but unused (cost view) | GLPI licences | Quarterly | IT Support |
| Vendor cases | Open vendor cases and their age against the contract terms | GLPI supplier tickets | Monthly | IT / Systems |

## 5. Documentation KPIs

| KPI | Definition | Source | Frequency | Owner |
|---|---|---|---|---|
| Pages past review | Pages whose review date has passed | BookStack + review reminder script | Monthly | IT |
| Knowledge-base coverage | Number of published KB articles mapped to service categories | BookStack / GLPI KB | Monthly | IT Support |

## 6. The monthly report (one page)

Order of the one-page report: (1) headline — SLA compliance and backlog; (2) ticket volume by
category; (3) first-contact resolution and reopen rate; (4) top 5 recurring issues **with the
permanent fix or problem record raised**; (5) asset reconciliation result; (6) renewals and licence
utilisation; (7) documentation overdue. The first report establishes a baseline and states clearly
that no "before" figure exists because nothing was tracked previously.

> **Status:** definitions only. **No value in this sheet is a measured result.** The first real
> figures are added to `../README.md` and the monthly report only after the system has run and the
> data has come from GLPI.
