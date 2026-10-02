# Halden Distribution Ltd. — L1 / L2 / vendor escalation matrix

**Purpose:** define who owns a support issue at each stage, when to hand it on, and exactly what to
include in the handoff — so nothing is bounced back for missing information.
**Owner:** IT (Muhammad Ibrahim Akmal) · **Review:** annually · **Applies to:** the service desk

> Halden Distribution Ltd. is the fictional company used in this portfolio; all suppliers named
> below are invented.

## 1. The tiers

| Tier | Who | Owns | Response commitment |
|---|---|---|---|
| **L1 — IT Support** | IT Support Officer | First-line triage, password resets and unlocks, printer faults, BitLocker recovery, software requests, mapped drives, general "how do I" questions (via the knowledge base) | Per the priority SLA |
| **L2 — SysAdmin** | Systems Administrator | AD and Group Policy, servers, network and VPN, security alerts, anything L1 cannot resolve with the knowledge base | Per the priority SLA after handoff |
| **L3 — Vendor / MSP** | External suppliers (fictional): hardware warranty, ISP, firewall vendor, line-of-business application vendor, offsite backup provider | Product faults, warranty claims, provider outages | Governed by each contract's support terms |

## 2. When to escalate L1 → L2

Escalate when any of these is true:

1. The knowledge-base steps do not fix the issue.
2. The cause is on a **server, the domain, the network or the firewall**, not the user's device.
3. A **security** concern is involved (suspicious email, suspected compromise, lost device).
4. The SLA timer is approaching 75% and the fix is not in sight.
5. More than one person or department is affected.

## 3. When to escalate L2 → L3

1. The fault is confirmed **hardware** within warranty or a support contract.
2. The fault is with a **provider's service** (ISP, line, hosted application).
3. A **software defect** or vendor-specific configuration is involved.
4. A warranty or contract **claim** must be raised.

## 4. What to include in a handoff (the template)

A handoff without this gets sent straight back. Copy it into the ticket when escalating:

```
Ticket:        <reference number and one-line title>
Requester:     <name, department, contact>
Priority:      P1 / P2 / P3 / P4  (and why)
Impact:        <who is affected and what they cannot do>
Started:       <date/time, and whether it is still happening>
Symptom:       <exact error message or behaviour>
What I tried:  <KB article used and the result; commands run; screenshots attached>
Affected item: <device name/asset tag, server, or service>
Escalating to: L2 (name) / L3 (vendor and contract reference)
```

## 5. Vendor cases

Every vendor case is raised as a ticket **linked to the supplier record** in GLPI, so the contract,
the account number and the support number travel with the case. Vendor access to Halden systems is
time-bound, MFA-protected and logged. The vendor management procedure is in
[`p09-vendor-management.md`](./p09-vendor-management.md).

## 6. The rule that keeps this matrix honest

If the same issue is escalated repeatedly, it does not stay a ticket: it becomes a **problem
record** with a permanent fix (or a new knowledge-base article, if it must stay manual). The point
of the matrix is not to pass work around; it is to get each issue to the right skill, once.

> **Status:** designed for the lab. Response commitments are targets; none have been measured yet.
