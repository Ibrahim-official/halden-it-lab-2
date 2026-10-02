# Halden Distribution Ltd. — Disaster Recovery Plan

| Field | Value |
|---|---|
| **Plan ID** | DRP-001 |
| **Version** | 0.9 (draft) |
| **Owner** | IT Lead |
| **Approver** | Managing Director — **signature pending** |
| **Applies to** | All Halden systems and sites |
| **Tested** | **No — no drill has been run yet.** Last drill: *(none)* |
| **Printed copy held off-site** | *(to be confirmed and recorded)* |

> **Status: this plan is untested.** The recovery time objectives in this document are **targets**. No
> drill has been run, so no achieved recovery time exists. Actual results will be recorded in
> `p08-dr-drill-report.md` after a timed drill. Halden Distribution Ltd. is fictional; this is a
> home-lab portfolio document.

---

## 1. Purpose and scope

This plan describes how Halden restores its critical services after a major failure or a deliberate
attack, who decides what, in what order systems are recovered, and how the outcome is measured against
the agreed objectives.

## 2. Roles

| Role | Responsibility | Named person |
|---|---|---|
| Disaster declared by | Confirms a disaster and authorises the recovery effort | Managing Director **with** IT Lead |
| Incident Lead | Runs the recovery, owns the clock, makes the calls | IT Lead |
| Recovery Operator | Performs restores, checks results | Systems |
| Business Liaison | Confirms each department's systems work before "all clear" | Department head (or deputy) |
| Communications | Updates staff and customers | MD or Office Manager |

In a small company one person may hold more than one role. Write down who actually holds each role
before the drill, not during the incident.

## 3. Contact steps

1. **Call the IT Lead** (primary) — or the deputy if unreachable within 15 minutes.
2. **Call the Managing Director** — decides on business impact, spend and communications.
3. **Call department heads** — to confirm priorities and to verify their systems after recovery.
4. **Call vendors only if needed** — off-site storage provider, ISP, hardware support. Keep vendor
   contacts in the printed copy; do not rely on a system being up to look them up.
5. **Record the time of every call.** The clock starts at the declaration, not at the first fix.

> Contact numbers are deliberately **not** in this repository. The filled contact list is kept in the
> printed off-site copy of this plan and in the IT Lead's records.

## 4. Declaration criteria

Declare a disaster when any of the following is true:

- Two or more Tier 0/1 systems are unavailable, or a Tier 0/1 system is expected to be down beyond its
  recovery objective.
- A domain controller is lost and the surviving controller cannot serve the business alone.
- The integrity of the backups themselves is in doubt.
- A ransomware or destructive attack has affected production systems.

Do not wait for certainty. Declaring and standing down costs little; declaring late costs a lot.

## 5. Recovery order and dependencies

Systems are recovered in dependency order: identity first, then files, then applications, then support.

```
0. Declare disaster, start incident response, preserve evidence, isolate the network
1. Clean infrastructure: hypervisor, then the firewall (config from source control)
2. Backup server health check; choose a restore point BEFORE the compromise
3. Restore DC01 in the sandbox, verify, then promote → confirm DNS and DHCP
4. Reset the compromised credentials (including krbtgt twice) and rotate privileged passwords
5. Restore FS01 → verify Finance and Sales share access
6. Restore LNX01 (order system) → verify with a Sales user
7. Restore OPS01 (service desk, monitoring) and SIEM01 (security monitoring)
8. Re-image workstations from the standard build → users return to work
9. Hand back to the business; run the lessons-learned review
```

## 6. Decision points

| Decision | Default position | Decided by |
|---|---|---|
| Restore in place, or rebuild from scratch? | Rebuild anything that was compromised; restore for plain hardware failure | Incident Lead |
| Which restore point? | The newest copy **older than the first suspicious event** | Incident Lead with the security timeline |
| Bring a restored domain controller straight into production? | No — verify and scan it in the sandbox first | Incident Lead |
| Accept data loss, or wait for an older copy? | Compare actual loss against the agreed objective; the business decides | MD with the Business Liaison |
| Tell customers now, or after recovery? | Now, if the outage will exceed the agreed objective | MD |

## 7. Recovery objectives (targets)

| Tier | Systems | Recovery time target | Data loss target |
|---|---|---|---|
| 0 | DC01/DC02, FW01 config | 2 hours | 24 hours |
| 1 | FS01, LNX01 | 4 hours | 1 hour |
| 2 | OPS01, SIEM01 | 24 hours | 24 hours |
| 3 | Workstations | 3 days (re-image) | not applicable |

Full detail and the sign-off table are in `p08-service-levels.md`. These are targets until a drill
measures them.

## 8. Key resources needed

| Resource | Location | Notes |
|---|---|---|
| Backup server credentials | owner password manager | **not** domain credentials |
| Backup encryption key | password manager **and** sealed copy with the offline media | losing it means losing the backups |
| An offline backup copy | stored off-site | the copy no attacker can reach |
| Firewall and server configuration | source control, plus the offline copy | used to rebuild clean |
| This plan | printed, off-site | the wiki may be unavailable |
| Vendor contacts | printed, off-site | do not depend on a system being up |

## 9. Communications

| Audience | What to say | Who |
|---|---|---|
| Staff | Is it a full or partial outage; whether to work from paper; when to expect an update | Communications |
| Customers / key suppliers | Only if the outage affects delivery; agreed wording, no technical detail | MD |
| Insurer / legal | After containment, with the evidence pack and the timeline | MD with the IT Lead |

Do not speculate about cause or blame during an incident. Give facts and next update times.

## 10. Testing and maintenance

- A **full recovery drill** is run at least twice a year and after any major change.
- The drill is timed with a stopwatch, and the results are recorded against the targets above.
- **Everything that breaks during a drill becomes an action with an owner and a date.**
- This plan is updated whenever a drill, incident or change shows it to be wrong.

## 11. Related documents

- Runbook (step-by-step): `../docs/runbooks/dr-drill-full-recovery.md`
- Ransomware and immutability: `../docs/runbooks/ransomware-immutability.md`
- Backup policy: `p08-backup-policy.md`
- Service levels: `p08-service-levels.md`
- Drill report: `p08-dr-drill-report.md`

---

## Approval

| Role | Name | Signature | Date |
|---|---|---|---|
| Plan owner (IT Lead) | Muhammad Ibrahim Akmal |  |  |
| Approver (Managing Director) |  |  |  |

> **Unsigned and untested.** This is a home-lab artifact for a fictional company.
