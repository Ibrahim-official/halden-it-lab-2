# P2: Identity Lifecycle and Access Governance — JML Automation, Hybrid Identity, MFA and Access Reviews

> Home-lab project in an isolated, simulated 85-user company ("Halden Distribution Ltd.").
> Presented as a home lab on the portfolio site — never as employment experience.
> All staff data used here is **synthetic** (see [`data/README.md`](./data/README.md)); the people
> count comes from the P1 dataset, and nothing here is real personal data.

**Status:** build kit complete — **lab execution pending** · **Build order:** 2 of 10 · **Depends on:** P1 (AD, OUs, AGDLP groups, FS01 shares)
**Plan:** [`docs/plan/P02-identity-lifecycle-access-governance.md`](../../docs/plan/P02-identity-lifecycle-access-governance.md) · **Design:** [`docs/00-design.md`](./docs/00-design.md) · **Site page source:** [`showcase.md`](./showcase.md)
**Progress:** see [`PROGRESS.md`](../../PROGRESS.md)

## Problem

At Halden, HR emails IT when someone joins, moves or leaves — sometimes. New starters wait two to
three days for the access they need; people who change department keep their old permissions
("permission creep"); leavers' accounts stay enabled for weeks; there is no MFA; and the Finance
Director cannot say who has access to payroll without an email to IT.

That is a business risk, not an IT detail. Credential abuse is the most common initial access vector
in reported breaches, and offboarding gaps and orphaned accounts are among the most frequent findings
in access audits. The process also fails in a way nobody can prove: because nothing is recorded, the
company cannot demonstrate that a leaver's access was removed.

## What I built

- **An automated joiner-mover-leaver engine** (`01-Invoke-HaldenJML.ps1`) that reconciles Active
  Directory to the HR source-of-truth export, keyed on `EmployeeID` and never on names.
- **A role model, not a copy of a colleague's groups**: `configs/role-matrix.csv` defines what each
  department and job title *should* have, and that file is the only place access is decided.
- **A mover path that removes as well as adds** — the old department's role groups are diffed against
  the desired set and stripped in the same run, which is what stops permission creep.
- **A leaver path in the order that matters**: capture the current group memberships to a per-user
  JSON snapshot first, then disable, reset the password, strip the groups, move the account to
  `OU=Disabled`, and hand off to the cloud steps (revoke sessions, block sign-in, then handle the
  mailbox before the licence).
- **Safety controls that make scheduling it defensible**: `-WhatIf` dry-run preview, a circuit
  breaker that aborts the whole run if more than 10% of the accounts in the export would be disabled,
  a protected-accounts list (service and break-glass accounts are never touched), an append-only
  audit log, and idempotency (a second run with the same export produces an empty plan).
- **Least privilege for the automation itself**: the engine runs as a group managed service account
  delegated rights over two OUs — `OU=Users,OU=Halden` and `OU=Disabled` — never as a Domain
  Administrator, with the `dsacls` evidence captured to file.
- **An identity-hygiene report** covering stale accounts (90+ days with no logon), password-never-
  expires and password-not-required accounts, disabled accounts retained for deletion, recursive
  privileged-group membership, and enabled accounts with no HR record.
- **Hybrid identity done per tier**: AD synced to Microsoft Entra ID via Cloud Sync scoped to
  `OU=Users,OU=Halden` only, with `_Admin` and `ServiceAccounts` excluded — admin accounts stay
  cloud-only and service accounts stay on-prem.
- **MFA and Conditional Access as version-controlled configuration**: five policies
  (CA001–CA005) in `configs/conditional-access/` deployed by script, created in **report-only**,
  reviewed in the sign-in logs, then enforced, with two monitored break-glass accounts created first
  and excluded from every policy.
- **An offline reference implementation and unit tests** (`02-Get-AdSnapshot.ps1`, `jml-plan.py`,
  `scripts/tests/test_jml_plan.py`) so the classify/diff/circuit-breaker rules can be reviewed and
  proven without touching the directory — 34 tests covering the joiner window, the mover diff
  (including that an unmanaged group is left alone), the leaver rules and the breaker ratio.
- **Business artefacts as deliverables**: an executive brief, a joiner-mover-leaver process and RACI
  document written for a non-technical HR reader, a role-based access model with department-head
  sign-off, a quarterly access-review pack with an action tracker, and the MFA rollout comms plan
  with a helpdesk surge plan.

## Architecture

![P2 identity lifecycle and access governance architecture](docs/diagrams/p02-architecture.svg)

The HR export is the single source of truth: the engine diffs the desired state it describes against
the live directory and acts on the difference, while every action lands in one append-only audit log.
Identities then sync to Microsoft Entra ID, where Conditional Access enforces MFA and blocks legacy
authentication — with break-glass accounts excluded and monitored so the control cannot become a
lock-out. The third panel of the diagram shows the as-is process beside the to-be process, because the
improvement is the deliverable, not the script.

The two rules that do the most work are small enough to quote. The circuit breaker is the one that
separates "helpful automation" from "the thing that disabled the company":

```powershell
# Abort the entire run if more than -CircuitBreakerPercent of the accounts in the export
# would be disabled in one go. Nothing has been changed at this point.
$threshold   = $hr.Count * $CircuitBreakerPercent / 100
$tripped     = ($hr.Count -gt 0) -and ($leaverCount -gt $threshold)
if ($tripped) { Write-Audit -Action 'CircuitBreakerTripped' -Target $HrFile -After $msg; exit 3 }
```

The companion Python implementation of the same rules (with tests) exists because a decision this
consequential should be reviewable without a domain controller in front of you.

## How to reproduce

Run in order. Every script is lab-guarded (it refuses to run outside `ad.halden.internal` / a host
carrying `/etc/halden-lab`) and supports `-WhatIf` where it changes state.

| Order | Where | Script | Does |
|---|---|---|---|
| 0 | LNX01 or a workstation | `scripts/00-Validate-HrExport.sh` | Validate the HR export (columns, unique `EmployeeID`, unique logon names, status, dates) **before** the engine may act |
| 1 | DC01 | `scripts/02-Get-AdSnapshot.ps1` | Export the offline AD view the Python planner and the tests use (read-only) |
| 1 | workstation | `scripts/jml-plan.py` | Compute and print the plan offline; `--dry-run`, no domain needed |
| 2 | DC01 | `scripts/03-New-JmlServiceAccount.ps1` | Create the `gmsa-jml` identity and delegate the two OUs, with `dsacls` evidence |
| 3 | DC01 | `scripts/01-Invoke-HaldenJML.ps1 -WhatIf` then without | The JML engine: dry-run preview, then apply |
| 3 | DC01 | `scripts/11-New-TestBadAccounts.ps1` then `scripts/02-Get-IdentityHygieneReport.ps1` | Seed the bounded test set, then produce the "before" hygiene report (`-Rollback` removes the test set) |
| 4 | DC01 | `scripts/05-Prepare-HybridIdentity.ps1 -Apply` | Add the cloud UPN suffix and update user UPNs |
| 4 | FS01 | Cloud Sync agent (GUI) | Install the agent and set its scope from `configs/cloud-sync-scope.json` — a runbook step |
| 5 | DC01 | `scripts/06-New-BreakGlassAccounts.ps1` | Create the two monitored break-glass accounts (do this **before** any CA policy) |
| 6 | DC01 | `scripts/07-New-ConditionalAccessPolicies.ps1 -State reportOnly` then `-State Enabled` | Deploy CA001–CA005 in report-only, review the sign-in logs, then enforce |
| 6 | DC01 | `scripts/08-Set-AuthenticationMethods.ps1` | Authenticator with number matching, SMS/voice off, Temporary Access Pass for onboarding |
| 6 | DC01 | `scripts/09-Invoke-ScubaGear.ps1 -Stage before` / `-Stage after` | CISA baseline assessment before and after, with a machine-readable summary |
| 7 | DC01 | `scripts/10-Export-AccessReview.ps1` | Produce the per-department access-review pack, then track actions to closure |
| 7 | DC01 | `scripts/04-Remove-LeaverCloudAccess.ps1 -EmployeeID <id>` | Cloud half of offboarding: revoke sessions, block sign-in, then remove the licence once the mailbox is handled |
| 8 | DC01 | `scripts/12-Get-IdentityAsBuilt.ps1` | Dump live facts for `docs/as-built.md` |

**Prerequisites:** P1 phases 3–4 complete (OU tree created, 85 synthetic users imported) so the engine
has a directory to reconcile against; PowerShell 7 with RSAT; the Microsoft.Graph modules for the
cloud steps; CISA ScubaGear installed and initialised. The Microsoft 365 Business Premium trial
includes Entra ID P1, which Conditional Access needs — **start it on the day Phase 3 begins**, not
before, and finish Cloud Sync, Conditional Access and ScubaGear inside the 30-day window. If the trial
lapses, the documented fallback is an Entra ID Free tenant with Security Defaults and Conditional
Access recorded as the design, not as a completed deployment.

**Two things to create before the first run.** On the lab Windows host, create the marker file that
every P2 script checks: `New-Item -ItemType File -Path 'C:\halden-lab-marker' -Force`. Then, once the
trial tenant exists (start of Phase 3), paste its `onmicrosoft.com` domain into
`configs/lab-tenant.json` under `labTenantDomain` — the four cloud scripts refuse to run until that
matches the tenant that is actually signed in, so the guard cannot be satisfied by accident.

Secrets (the break-glass passwords, the gMSA context) are generated and written only to git-ignored
paths or the owner's password manager — never to the repository. Tenant IDs, tenant domains, object
IDs and UPNs are sanitized out before anything is published.

**Snapshot before every phase** (`snap-p2-ph<N>-before`). **Rollback:** revert the snapshot and re-run
the previous phase's idempotent scripts. Cloud controls are configuration and are backed out by
returning the Conditional Access policies to report-only; a wrong leaver is restored from
`logs/leavers/<EmployeeID>.json` after the HR record has been corrected. Reverting a *domain
controller* snapshot is a last resort — fix DC problems forward, because a revert can disturb
replication.

## Results

**Not measured yet.** This build kit has been written but not yet executed in the lab, so this table
is deliberately empty rather than filled with plausible-looking numbers. Each row is a real
measurement with a file in `evidence/public/` as its source, added when the phase runs.

| Metric | Before | After | Source |
|---|---|---|---|
| Joiner lead time (HR record to account ready) | not measured | not measured | — |
| Leaver revocation time (HR record to sessions revoked) | not measured | not measured | — |
| Enabled accounts with no HR record (orphans) | not measured | not measured | — |
| Enabled accounts with no logon in 90+ days | not measured | not measured | — |
| Excess permissions found by the access review | not measured | not measured | — |
| MFA coverage (% of users required to use MFA) | not measured | not measured | — |
| CISA ScubaGear passing checks (aad/exo/teams) | not measured | not measured | — |
| Access-review actions closed vs raised | not measured | not measured | — |

The measurement method for each row is written down in `business/p2-kpi.md` §1, so the number can be
checked rather than trusted.

## Acceptance tests

| Test | Expected | Actual | Pass |
|---|---|---|---|
| New Sales hire in the HR file | Account, role groups and home drive created; audit entry | not run | ☐ |
| Finance → Operations transfer | Loses the Finance access, gains the Operations access, old groups gone, in one run | not run | ☐ |
| Leaver with the end date today | Disabled, sessions revoked, groups captured, moved within 15 minutes | not run | ☐ |
| Corrupted HR file (half the rows marked leaver) | Circuit breaker aborts, alert raised, nothing changed | not run | ☐ |
| User signs in with a password only | Challenged for MFA (CA001) | not run | ☐ |
| Legacy mail client sign-in | Blocked (CA002) and visible in the sign-in logs | not run | ☐ |
| Break-glass account signs in | Not challenged, and the sign-in is recorded for monitoring | not run | ☐ |
| Re-run the engine with no HR changes | Empty plan; no duplicates, no errors (idempotent) | not run | ☐ |
| `00-Validate-HrExport.sh` against a truncated export | Fails with a clear reason; the engine is not run | not run | ☐ |
| Test accounts removed with `11-New-TestBadAccounts.ps1 -Rollback` | The environment no longer contains the fixtures | not run | ☐ |

## Business deliverables

| Artifact | For | File |
|---|---|---|
| Executive brief (1 page) — the issue, the change, the cost, what the business must do | Management | `business/p2-exec-brief.md` |
| JML process and RACI — joiner, mover and leaver, written so a non-technical HR reader can follow it | HR, line managers, department heads | `business/p2-jml-process-and-raci.md` |
| Role-based access model with a department-head sign-off block | Department heads approve access, not IT | `business/p2-role-matrix.md` (+ `configs/role-matrix.csv`) |
| Quarterly access-review pack with a tracker that follows actions to closure | Department heads; the audit trail | `business/p2-access-review-pack.md` |
| MFA rollout comms plan — staff email, one-page setup guide, FAQ and helpdesk surge plan | All staff, via department heads | `business/p2-mfa-rollout-comms.md` |
| KPI report — before/after measures, each with its measurement method | Management; feeds the P10 governance dashboard | `business/p2-kpi.md` |
| Change record (risk, test plan, backout) | Management / audit trail; feeds the P10 change log | `business/p2-change-record.md` |

## Lessons learned

- **The process design came before the script, and that was right.** Building the as-is/to-as-is
  comparison first showed that the real problem was a missing HR field, not missing automation. An
  engine that reconciles to a record nobody maintains just fails faster.
- **Removing access is harder to get right than granting it.** The leaver order (snapshot, then
  disable, then strip, then move) exists because the group snapshot is worthless once the groups are
  gone, and because "disable first" is how you get an audit gap.
- **A safety control has to be a number, not a promise.** "Don't run it on a bad file" is not a
  control; "abort if more than 10% of the export would be disabled" is. I also found while building
  the offline planner that comparing this run's leavers against the count of accounts in AD tripped
  the breaker on a single genuine leaver — the two counts have to share a denominator, and the tests
  now pin that down.
- **Some steps refuse to be scripted, and pretending otherwise is a lie.** The Cloud Sync agent is a
  GUI install. The scope, the UPNs and the exclusions around it are scripted, and the install itself
  is a runbook step with a screenshot, recorded as such.
- **Least privilege has to apply to the tool too.** The engine runs as a gMSA delegated over two OUs.
  A scheduled job that can disable any account in the directory is a bigger risk than the manual
  process it replaced.

## Interview notes

**"How do you stop permission creep?"** A role matrix defines the desired state — department and job
title to role groups. The mover path recomputes the desired groups, compares them with the account's
current membership, and **removes the extras as well as adding the new ones in the same run**, driven
by HR's change rather than by a ticket someone may forget. The diff goes into the audit log, so
"what did this person lose when they moved?" is answerable months later. I also limited removal to the
groups named in the matrix: a project distribution list is reported, not revoked, because an
automated tool should not silently remove an access nobody asked it to manage.

**"What if HR sends a bad file?"** Three defences in order. First, a dry run that prints the entire
plan and changes nothing. Second, a circuit breaker: if more than 10% of the accounts in the export
would be disabled in one run, the whole run aborts, writes an alert line and exits with code 3 —
nothing is changed. Third, an append-only audit log plus a per-user group snapshot taken *before* the
groups are stripped, so a wrong leaver can be re-enabled and restored from a file rather than from
memory. A scheduled job that can silently disable the company is not a control.

**"How would you roll out MFA without chaos?"** In stages, and never all at once. Create the two
break-glass accounts first and exclude them from every policy. Turn the policies on in
**report-only** and read the sign-in logs, so you see who *would* be challenged before anyone is
blocked. Publish the comms and the one-page setup guide, pilot with one department, issue Temporary
Access Passes so onboarding is not blocked, brief the helpdesk for a surge with the fastest fix
(a TAP, not a password reset) and count the calls per department as the real measure of the rollout.
Then enforce, and verify the break-glass accounts still sign in with a password alone.

**"Why does the automation run as a gMSA instead of a Domain Admin?"** Because the engine's job is to
create, update and disable user objects in two OUs. I created `gmsa-jml`, ran the Delegation of
Control steps and verified the result with `dsacls`, so the account has exactly the rights it needs
over `OU=Users,OU=Halden` and `OU=Disabled` and nothing else. If the scheduled task were compromised,
the blast radius is two OUs rather than the whole directory — least privilege applied to the tool, not
only to the people. I checked that it is not a member of Domain Admins and captured that as evidence.
