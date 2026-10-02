# Halden Distribution Ltd. — Service Level Agreement (SLA) policy

**Purpose:** define how quickly IT responds to and resolves support requests, so staff know what to
expect and IT can be measured against a published target.
**Owner:** IT (Muhammad Ibrahim Akmal) · **Approver:** Managing Director · **Review:** annually
**Applies to:** all IT services in the [service catalogue](./p09-service-catalogue.md)

> This document defines **targets**. It does not report performance: actual SLA compliance is
> measured from real ticket data and is **not** stated anywhere until it has been measured
> (see `../docs/as-built.md` and the project README).

## 1. Where this applies

The SLA covers the services IT provides to Halden staff: the service desk itself, accounts and
access, the shared drives, email and Microsoft 365, printing, the network and VPN, and the devices
IT manages. It does **not** cover third-party services that fail outside IT's control (for example
an ISP outage), although IT owns the communication and the escalation to the provider for those.

## 2. Business hours

The clock runs **Monday–Friday, 08:00–18:00 `Asia/Karachi`**, excluding public holidays. A request
raised outside those hours starts its clock at the next opening time. This matters: an SLA defined
as "4 hours" without a calendar is really an overnight commitment nobody intended.

Two measures are used:

- **TTO — Time To Own:** the time until a named person or team has taken the ticket and started work.
- **TTR — Time To Resolve:** the time until the ticket is resolved (fixed, or a workaround agreed
  with the requester).

## 3. Priority and targets

Priority comes from Impact × Urgency, set by the desk at triage (and adjusted by the business
rules). The user's own sense of urgency is an input, not the final word.

| Priority | Impact × Urgency | Example | TTO | TTR |
|---|---|---|---|---|
| **P1 Critical** | High × High | Whole site down, ransomware, payroll-day failure | 15 minutes | 4 hours |
| **P2 High** | High × Medium | A department cannot work, VPN down for all remote users | 1 hour | 8 hours |
| **P3 Medium** | Medium × Medium | One user cannot work, a workaround exists | 4 hours | 2 business days |
| **P4 Low** | Low × Low | Service request or a cosmetic issue | 1 business day | 5 business days |

The machine-readable targets and business rules live in `configs/glpi-sla-priorities.json`. The
deadline arithmetic (weekend and holiday rollover) is proven by unit tests
(`scripts/tests/test_sla.py`) so that "8 hours" is computed the way the policy says it is.

## 4. Escalation

A ticket is escalated automatically when **75% of its TTR has been used** without resolution: the
L2 group is notified and the ticket is marked Escalated. Human escalation follows the
[escalation matrix](./p09-escalation-matrix.md):

- **L1 IT Support** — first line: password resets, printers, BitLocker recovery, software requests,
  general triage.
- **L2 SysAdmin** — systems, AD/GPO, servers, network and VPN, security alerts.
- **L3 Vendor / MSP** — hardware warranty, ISP, firewall vendor, line-of-business application.

## 5. Rules the business rules enforce

1. **Security reports always go to L2** with priority P2, never left in the L1 queue.
2. **Payroll-day failures in Finance** are treated as P1 even if they look like a single-user fault.
3. **A failed or missed backup restore test** opens a P2 Backup ticket automatically.
4. **Recurring issues become problem records** — three or more tickets for the same fault triggers a
   problem record and a permanent fix, not a fourth workaround.

## 6. What the SLA does not promise

- A **fix** where the fault is with a third party — it promises ownership, communication and
  escalation, with the provider's own response governed by their contract.
- **Out-of-hours cover** — there is none in this model; P1 events outside business hours are handled
  on a best-effort basis and recorded as such. (If the business wants 24/7 cover, that is a separate
  decision with a cost.)
- **Restoring data beyond the backup window** — recovery is limited by the backup design (P8).

## 7. Review and reporting

Performance is reported monthly (volume, first-contact resolution, SLA compliance, top recurring
issues). Targets are reviewed annually and whenever the business changes. **No performance figure is
published until it has been measured** from real ticket data; the reporting definitions are in
`p09-kpi-reporting.md`.

## Business approval

| Approver | Role | Date | Signature / approval |
|---|---|---|---|
|  | Managing Director |  |  |
|  | IT Manager |  |  |

> **Status:** drafted for the lab; **unsigned** until the business review actually happens.
> Halden Distribution Ltd. is the fictional company used for this portfolio.
