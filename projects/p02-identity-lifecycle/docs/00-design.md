# P2 — Phase 0: Design document (design before you build)

**Project:** P2 Identity Lifecycle and Access Governance (JML automation, hybrid identity, MFA, Conditional Access, access reviews)
**Company:** Halden Distribution Ltd. (fictional, 85 users) · **Domain:** `ad.halden.internal`
**Status:** Phase 0 complete · **Owner:** Muhammad Ibrahim Akmal · **Mode:** A (Advisor)
**Spec:** [`docs/plan/P02-identity-lifecycle-access-governance.md`](../../../docs/plan/P02-identity-lifecycle-access-governance.md)
**Depends on:** P1 (OU tree, AGDLP groups, FS01 shares, `OU=Disabled`)

> Why design first: an identity project is a *process* project with a PowerShell engine attached.
> If the HR file, the role model and the SLAs are not agreed with the business first, the automation
> simply moves the same disagreements faster. This document also draws the as-is process so the
> improvement can be pointed at, not asserted.

---

## 1. Goal and scope

Replace the manual, email-driven account process with an automated joiner-mover-leaver (JML)
pipeline driven by an HR source-of-truth export, sync identities to Microsoft Entra ID, enforce MFA
through Conditional Access, and introduce quarterly access reviews with departmental sign-off.

In scope: the AD-side JML engine, stale/privileged account hygiene, hybrid identity and the cloud
controls, access reviews, and the business artefacts (process map, role matrix, comms, KPI report).

Out of scope: privileged-access tiering and Windows LAPS (P3), endpoint hardening (P4), the
SIEM alerts that watch the break-glass accounts (P7), and the CMDB that will hold the joiner/mover
tickets (P9).

## 2. Business context (why this exists)

At Halden, HR emails IT when someone joins, moves or leaves — sometimes. New starters wait two to
three days for access; people who change department keep their old permissions; leavers' accounts
stay active for weeks; and there is no MFA. The Finance Director cannot answer "who has access to
payroll?" without an email to IT.

**Market evidence:** credential abuse is the most common initial access vector (about 22% of
breaches — Verizon 2025 DBIR), MFA cut account-compromise risk by 99.22% in Microsoft's
peer-reviewed study, and offboarding gaps and orphaned accounts are among the most common findings
in access audits. Sources: `docs/plan/00-research-and-selection.md` §2.

**Success = the measurable criteria** in the P2 plan §3 (joiner ready before day 1, mover removes
extras in the same run, leaver revoked within 15 minutes, zero unexplained stale accounts, MFA for
100% of users, ScubaGear before/after, quarterly review signed off). None of these are numbers yet;
each is a test whose result is pasted into `README.md` when the lab run happens.

## 3. Design principles

1. **One source of truth.** The HR export is the authority for who should have access. AD is
   reconciled *to* it, never edited by hand for joiners, movers or leavers.
2. **Keyed on `EmployeeID`, never on names.** Names change, collide and get misspelt; the employee
   number is stable and it is what HR already maintains.
3. **Desired state, then diff.** The role matrix defines what a role *should* have. The mover path
   removes anything outside it, which is what stops permission creep.
4. **Safe by default.** Dry-run first, a circuit breaker for mass changes, protected accounts that
   are never touched, and an append-only audit log.
5. **Least privilege for the automation itself.** The engine runs as a gMSA delegated rights over
   two OUs — not Domain Admin.
6. **Evidence first.** Every phase defines what to screenshot/save *before* it runs (§11).
7. **Snapshot before every phase** (§12); every change gets a rollback note.

## 4. Current state at Halden (as-is)

| Step | Who | What happens today | Failure point |
|---|---|---|---|
| 1 | HR | Types the new starter onto a spreadsheet; emails IT "when they remember" | No trigger; late or missing |
| 2 | Line manager | Chases IT verbally for access | No record of what was requested or approved |
| 3 | IT | Creates the account by hand in ADUC, copies the groups of "someone similar in the department" | Inconsistent; copies the previous person's permissions, including their mistakes |
| 4 | HR | Emails IT when someone changes department | Old-department groups are rarely removed — permission creep |
| 5 | HR | Emails IT when someone leaves — sometimes weeks later | The account stays enabled; no record of what it could reach |
| 6 | IT | Nothing reconciles HR against AD | Orphaned accounts and stale access are found only by accident |

**Measured today:** none of this has been measured in the lab. The as-is column is the process
design; the "before" figures that will appear in the KPI report come from a timed dry run and the
hygiene report in Phase 2, not from imagination.

## 5. To-be process (joiner, mover, leaver)

```
HR export (nightly CSV)                     Exception request (approved by dept head)
        |                                                  |
        v                                                  v
  Invoke-HaldenJML.ps1  ---- diff HR desired state vs AD current state ----+
        |                     |                     |                      |
     JOINER                 MOVER                 LEAVER                   |
        |                     |                     |                      v
        v                     v                     v             logs/jml-audit.csv
  AD DS (P1 OUs, AGDLP groups, FS01 home drive)  -->  OU=Disabled        (append-only)
        |
        v
  Entra Cloud Sync (scope OU=Users, excludes _Admin/ServiceAccounts)
        |
        v
  Microsoft Entra ID  -->  Conditional Access CA001-CA005 (MFA, block legacy auth)
        |                  break-glass accounts (excluded, monitored)
        |                  ScubaGear assessment (before / after)
        v
  Quarterly: Export-AccessReview.ps1 --> per-department review --> head signs off --> removals --> actions closed
```

### 5.1 Joiner

1. HR adds the row to the export with `Status = Active` and a `StartDate`.
2. The engine creates the account in the department OU, sets department, title, manager and
   `EmployeeID`, and stamps `extensionAttribute1 = JML-Managed`.
3. Role groups come from the role matrix (never copied from another user).
4. Home drive folder is created on FS01 with the user granted access to their own folder only.
5. The initial password is random, must be changed at first logon, and is written to a
   git-ignored file for secure handover to the line manager — never emailed in clear text.
6. A Temporary Access Pass is the preferred onboarding method once the cloud phase is live.

### 5.2 Mover

1. HR changes `Department` and/or `Title` in the export.
2. The engine recomputes desired groups from the role matrix, diffs them against current
   membership, **removes the extras and adds the missing ones in the same run**, updates the
   attributes, and moves the account to the new department OU.
3. The diff is written to the audit log so the "what did they lose?" question is answerable.

### 5.3 Leaver (order matters)

1. Record current group memberships to `logs/leavers/<EmployeeID>.json` (rehires and investigations).
2. Disable the account and reset the password to a random 64-character value.
3. Remove all groups except `Domain Users`.
4. Set `description = "Leaver <date> ticket #<n>"` and move the account to `OU=Disabled`.
5. Cloud: revoke refresh tokens (`Revoke-MgUserSignInSession`), block sign-in, handle the mailbox
   before removing the licence.
6. Deletion is scheduled at +90 days by a separate step, with a report first — disable, retain,
   delete, because of legal holds and rehires.

### 5.4 Safety features

| Feature | What it does | Why |
|---|---|---|
| `-WhatIf` dry run | Prints the planned changes and changes nothing | Review before acting |
| Circuit breaker | Aborts if more than 10% of accounts would be disabled in one run | A bad HR export must not wipe out the company |
| Protected accounts | `data/protected-accounts.txt` is never touched | Service and break-glass accounts are not people |
| Append-only audit log | Timestamp, action, target, before, after, operator | Answers "who changed what, when" |
| Leaver snapshots | Group membership captured to JSON before removal | Rehire and investigation |
| Delegated gMSA | The scheduled task runs least-privilege over two OUs | Not Domain Admin |

## 6. Data model

### 6.1 HR export (`data/hr-export.csv`)

| Column | Meaning | Notes |
|---|---|---|
| `EmployeeID` | Stable key | **The join key. Never use names.** |
| `First`, `Last` | Display name | Used for the `first.last` logon name |
| `Department` | Maps to the department OU and the role matrix | Drives the OU and group set |
| `Title` | Job title | Combined with department to select role groups |
| `ManagerID` | Manager's `EmployeeID` | Resolved to the manager's account for the `Manager` attribute |
| `Status` | `Active` or `Leaver` | The lifecycle trigger |
| `StartDate`, `EndDate` | Employment dates | Start drives the joiner window; End drives the leaver action |

### 6.2 Role matrix (`configs/role-matrix.csv`)

`Department,Title,RoleGroups,ResourceGroups,Applications` — the *desired* group set for a role as a
semicolon-separated list of `G_` groups. Resource (`DL_`) groups are reached through the `G_` groups
by P1's AGDLP model, so the matrix only names role groups. `*` is allowed in `Title` for a
department-wide default (for example `Operations,*`).

### 6.3 Reference implementation

`scripts/jml-plan.py` (with `scripts/lib/jml_plan.py`) computes the same plan in Python without
needing a domain: it is the unit-tested reference for the classify/diff/circuit-breaker logic, and a
way to inspect what a run *would* do. The PowerShell engine is the component that acts.

## 7. Hybrid identity and cloud controls

| Item | Decision |
|---|---|
| Sync tool | **Entra Cloud Sync** (lightweight agent) on FS01 — not on a DC |
| Sync scope | `OU=Users,OU=Halden` only; `_Admin` and `ServiceAccounts` excluded |
| Admin accounts | Cloud-only or on-prem only — **never synced**. Tier 0 stays separate |
| UPN | Users get a UPN that matches the tenant's verified/`onmicrosoft.com` domain |
| Break-glass | 2 cloud-only accounts, excluded from all CA policies, sign-in monitored (P7) |
| MFA | Microsoft Authenticator with number matching; SMS/voice disabled where possible |
| Onboarding | Temporary Access Pass issued by the joiner flow |
| Conditional Access | CA001–CA005, created in **report-only**, reviewed in the sign-in logs, then **On** |
| Licences | Removed only after mailbox handling, on the leaver path |
| Assessment | CISA ScubaGear, before and after |

### Conditional Access policy set

| Policy | Users | Condition | Control |
|---|---|---|---|
| CA001 — Require MFA — All users | All (except break-glass) | All cloud apps | Require MFA |
| CA002 — Block legacy authentication | All | Client apps: Exchange ActiveSync + other clients | Block |
| CA003 — Phishing-resistant MFA for admins | Directory roles | All apps | Authentication strength: phishing-resistant |
| CA004 — Block sign-in from unapproved locations | All | Named locations | Block |
| CA005 — Require MFA to register security info | All | User action: register security info | Require MFA / trusted location |

The definitions live in `configs/conditional-access/CA001…CA005.json` and are applied by
`07-New-ConditionalAccessPolicies.ps1` (report-only by default, `-State Enabled` to enforce).

## 8. The trial and the timing

The free Microsoft 365 Business Premium trial lasts 30 days and includes Entra ID P1 (which
Conditional Access needs). **Start the trial on the day Phase 3 begins** — not before — and finish
Cloud Sync, Conditional Access and ScubaGear inside the window. If the trial lapses before the cloud
phase is finished, the fallback is an Entra ID Free tenant with **Security Defaults** (tenant-wide
MFA), and Conditional Access is documented as the design that the licensed tenant deploys. That
fallback is recorded honestly rather than hidden.

## 9. Build phases and evidence plan

| Phase | Deliverable | Evidence to capture |
|---|---|---|
| 0 | This design document, the as-is/to-be process map, the role matrix, the SLAs | `business/p2-jml-process-and-raci.pdf`, `business/p2-role-matrix.pdf` |
| 1 | JML engine + gMSA delegation + audit log | Dry-run output, audit CSV excerpt, leaver JSON, `dsacls` output |
| 2 | Stale/privileged account hygiene report | `reports/identity-hygiene-<date>.html` (before), hydrated by lab-seeded test data |
| 3 | Hybrid identity, MFA, Conditional Access, ScubaGear | Cloud Sync status, CA report-only then On, sign-in log (MFA prompt + blocked legacy), ScubaGear before/after |
| 4 | Quarterly access review pack | Per-department export, signed review sheet, action tracker |
| 5 | Six lifecycle scenarios | Test log with the corrupted-file circuit-breaker abort |
| 6 | README, KPI table, CV bullets | Real numbers only; otherwise "not measured" |

## 10. Lab host, scope and prerequisites

- Runs on the P1 lab: DC01/DC02 (AD), FS01 (file services and the Cloud Sync agent), WS01 (a real
  browser for the MFA prompt and a legacy-auth test), LNX01 (the HR export validator runs here).
- Hybrid identity needs internet access for the Cloud Sync agent and the Graph calls; the lab's WAN
  is FW01's NAT, so no lab host is exposed publicly.
- **Prerequisite:** P1 phases 3–4 complete (OUs created, 85 users imported) so the engine has a
  directory to reconcile against.

## 11. Evidence plan

Named to the AGENTS.md 4.5 rule `pXX-phN-<what>-<before|after|result>.<ext>`:
`p02-ph1-jml-whatif-result.txt`, `p02-ph1-jml-audit-result.csv`, `p02-ph1-leaver-snapshot-result.json`,
`p02-ph1-gmsa-delegation-result.txt`, `p02-ph2-hygiene-before.html`,
`p02-ph3-cloudsync-status-result.png`, `p02-ph3-ca-reportonly-result.png`,
`p02-ph3-mfa-signinlog-result.png`, `p02-ph3-legacy-blocked-result.png`,
`p02-ph3-scubagear-before.json`, `p02-ph3-scubagear-after.json`,
`p02-ph4-access-review-signed-result.pdf`, `p02-ph5-circuitbreaker-abort-result.txt`.

## 12. Snapshot and rollback plan

- **Before every phase:** take a hypervisor snapshot of each VM the phase touches, named
  `snap-p2-ph<N>-before`. Rollback = revert that snapshot and re-run the previous phase's scripts,
  which are idempotent.
- **Cloud caution:** a Conditional Access policy that locks everyone out is the classic identity
  own-goal. The defence is the order in this design — **break-glass accounts first**, **report-only
  first**, then enable — and the break-glass accounts are excluded from every policy in
  `configs/conditional-access/`.
- **Group-membership rollback:** every leaver run writes `logs/leavers/<EmployeeID>.json` *before*
  removing groups, so a wrong leaver can be restored from that snapshot rather than from memory.
- Phase 0 changed nothing in the lab, so no snapshot was needed. **Phase 1 does change things.**

## 13. Risks

| Risk | Mitigation |
|---|---|
| A bad HR export disables a large part of the company | Circuit breaker (>10%), dry run, protected accounts, audit log |
| Using names rather than `EmployeeID` | EmployeeID is the join key in the export and the engine |
| Permission creep on moves | Mover diffs desired vs actual and removes extras in the same run |
| Locking out of the tenant with Conditional Access | Report-only first; two excluded break-glass accounts; staged enablement |
| Admin accounts leaking into the cloud | Cloud Sync scope excludes `_Admin`; admins stay cloud-only |
| Trial expires mid-build | Start at Phase 3; fallback documented (§8) |
| Deliberately bad accounts seeded for Phase 2 left behind | They are created by a named test script and removed at rollback (Phase 2 runbook) |
| The engine runs with too much power | Delegated gMSA scoped to the Users and Disabled OUs, verified with `dsacls` |

## 14. Interview notes (phase 0)

**"How do you stop permission creep?"** A role matrix defines the desired state; the mover process
computes desired groups, `Compare-Object`s them with the account's current membership and removes
the extras as well as adding the new ones — in the same run, from HR's change, not from a ticket
someone may forget. The audit log records what was removed.

**"What if HR sends a bad file?"** Three defences in order: a dry run that changes nothing, a
circuit breaker that aborts the whole run if more than 10% of accounts would be disabled, and an
append-only audit log plus per-user group snapshots so a wrong leaver can be restored. A scheduled
job that can silently disable the company is not a control.

**"How would you roll out MFA without chaos?"** Publish the comms and the setup guide first, pilot
with IT, issue Temporary Access Passes so onboarding is not blocked, put Conditional Access in
report-only and read the sign-in logs, create the break-glass accounts before enabling anything,
brief the helpdesk for a surge, then enforce.

**"Why does the automation run as a gMSA and not Domain Admin?"** The engine only needs to manage
user objects in two OUs. Giving it delegated rights over just those OUs means a compromised
scheduled task cannot touch the rest of the directory — least privilege applied to the tool, not
only to the people.

---

*Next step: Phase 1 — the JML engine (plan §Phase 1). Snapshot DC01 first; run `-WhatIf` and read the
plan before anything is changed. Mode A: the owner runs the commands and pastes the output back.*
