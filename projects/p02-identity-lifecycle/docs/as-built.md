# P2 as-built — Halden Distribution Ltd. identity lifecycle and access governance

> **Status: build kit complete, lab execution pending.** This document records the *designed*
> configuration from [`00-design.md`](./00-design.md) and is written so that the *measured* facts
> can be pasted straight in. Nothing in this file is presented as a captured result: the
> **Verified** column stays empty (☐) until the matching script has actually been run in the lab and
> `12-Get-IdentityAsBuilt.ps1` has produced its output.
>
> **How to finish this document:** run `.\scripts\12-Get-IdentityAsBuilt.ps1` on DC01 and
> `.\scripts\10-Export-AccessReview.ps1` for the access view. They write Markdown into
> `evidence/raw/`. Sanitize that output (AGENTS.md 4.6 — no tenant IDs, object IDs or real
> addresses) and paste it into the sections below, replacing *(designed)* with *(verified)*.
> Evidence files go in `evidence/public/` with names like `p02-ph1-jml-audit-result.csv`.

## 1. Environment summary

| Item | Designed value | Verified |
|---|---|---|
| Domain | `ad.halden.internal` | ☐ |
| Directory source of truth | `data/hr-export.csv` (synthetic), keyed on `EmployeeID` | ☐ |
| Engine entry point | `scripts/01-Invoke-HaldenJML.ps1` | ☐ |
| Audit log | `logs/jml-audit.csv` (append-only, git-ignored) | ☐ |
| Leaver snapshots | `logs/leavers/<EmployeeID>.json` (git-ignored) | ☐ |
| Automation identity | `gmsa-jml` with delegated rights over two OUs | ☐ |
| Cloud sync | Entra Cloud Sync agent on FS01, scope `OU=Users,OU=Halden` | ☐ |
| Conditional Access | CA001–CA005 in `configs/conditional-access/` | ☐ |
| Trial | Microsoft 365 Business Premium (30 days), started at Phase 3 | ☐ |

## 2. Role model *(designed)*

Role groups come from `configs/role-matrix.csv`; resource access is reached through P1's AGDLP model,
so the matrix names only `G_` role groups.

| Department | Title pattern | Role groups applied |
|---|---|---|
| Management | `*` | `G_Management`, `G_AllStaff` |
| Finance | `*` | `G_Finance_Staff`, `G_AllStaff` |
| HR | `*` | `G_HR_Staff`, `G_AllStaff` |
| Sales | `*` | `G_Sales_Staff`, `G_AllStaff` |
| Operations | `*` | `G_Operations_Staff`, `G_AllStaff` |
| IT | `*Systems*` | `G_IT_Staff`, `G_IT_LinuxAdmins`, `G_AllStaff` |
| IT | `*` | `G_IT_Staff`, `G_AllStaff` |

| Fact | Designed value | Verified |
|---|---|---|
| Managed groups source | `configs/role-matrix.csv` | ☐ |
| Accounts stamped `extensionAttribute1 = JML-Managed` | all engine-created accounts | ☐ |
| Groups the mover is allowed to remove | only role groups in the matrix (plus `G_AllStaff`) | ☐ |
| Membership changes on a move | old role removed and new role added in one run | ☐ |

## 3. Joiner *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Trigger | `Status = Active` and no AD account with that `EmployeeID` | ☐ |
| Creation window | `StartDate` within the joiner lead (default 7 days) | ☐ |
| OU | `OU=<Department>,OU=Users,OU=Halden` | ☐ |
| Attributes set | Department, Title, EmployeeID, Manager, Office | ☐ |
| Home drive | `\\fs01.ad.halden.internal\Users$\<sam>` created, user granted access to their own folder | ☐ |
| Initial password | Random, must change at first logon, written only to a git-ignored file | ☐ |
| Handover | To the line manager over the agreed secure channel — never clear-text email | ☐ |

## 4. Mover *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Trigger | AD `Department` or `Title` differs from the HR export | ☐ |
| Desired groups | Recomputed from the role matrix | ☐ |
| Removal scope | Managed role groups not in the desired set | ☐ |
| Attributes updated | Department, Title, Manager | ☐ |
| OU move | To the new department OU | ☐ |
| Diff recorded | Added and removed groups written to `logs/jml-audit.csv` | ☐ |

## 5. Leaver *(designed)*

Order is deliberate; each step is logged.

| Step | Action | Verified |
|---|---|---|
| 1 | Record current group memberships to `logs/leavers/<EmployeeID>.json` | ☐ |
| 2 | Disable the account; reset the password to a random 64-character value | ☐ |
| 3 | Remove all groups except `Domain Users` | ☐ |
| 4 | Set `description = "Leaver <date> ticket #<n>"`; move to `OU=Disabled` | ☐ |
| 5 | Cloud: revoke sign-in sessions, block sign-in, retain mailbox, remove licence after handling | ☐ |
| 6 | Deletion scheduled at +90 days by a separate step, with a report first | ☐ |

## 6. Safety controls *(designed)*

| Control | Designed value | Verified |
|---|---|---|
| Dry run | `-WhatIf` prints the plan and changes nothing | ☐ |
| Circuit breaker | abort if more than 10% of accounts would be disabled in one run | ☐ |
| Protected accounts | `data/protected-accounts.txt` is never modified or disabled | ☐ |
| Audit log | timestamp, action, target, before, after, operator | ☐ |
| Idempotency | a second run with the same export makes no changes | ☐ |
| Automation identity | `gmsa-jml`, delegated over `OU=Users,OU=Halden` and `OU=Disabled` | ☐ |

## 7. Stale and privileged account hygiene *(designed)*

| Check | Designed value | Verified |
|---|---|---|
| Stale accounts | enabled users with no logon in 90+ days (`lastLogonTimestamp`, ~14-day accuracy) | ☐ |
| Password never expires | enabled users with `PasswordNeverExpires` | ☐ |
| Password not required | users with `PasswordNotRequired` | ☐ |
| Privileged members | recursive membership of Domain/Enterprise/Schema Admins, Administrators, Account/Backup Operators | ☐ |
| Report | `reports/identity-hygiene-<date>.html` with styling and a summary count | ☐ |
| Test data | a small, named set of deliberately bad accounts is seeded only for the "before" run and removed at rollback | ☐ |

## 8. Hybrid identity *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Agent host | FS01 (not a domain controller) | ☐ |
| Scope | `OU=Users,OU=Halden` only | ☐ |
| Exclusions | `_Admin` and `ServiceAccounts` OUs | ☐ |
| Admin accounts | cloud-only or on-prem only — never synced | ☐ |
| UPN | matches the tenant's verified/`onmicrosoft.com` domain | ☐ |
| Break-glass | 2 cloud-only accounts, excluded from all CA policies, sign-in monitored | ☐ |

## 9. Conditional Access and authentication methods *(designed)*

| Policy | State (designed) | Control | Verified |
|---|---|---|---|
| CA001 — Require MFA — All users | report-only, then On | Require MFA (excludes break-glass) | ☐ |
| CA002 — Block legacy authentication | report-only, then On | Block (EAS + other clients) | ☐ |
| CA003 — Phishing-resistant MFA for admins | report-only, then On | Authentication strength | ☐ |
| CA004 — Block unapproved locations | report-only, then On | Block (named locations) | ☐ |
| CA005 — Require MFA to register security info | report-only, then On | Require MFA / trusted location | ☐ |

| Authentication method | Designed value | Verified |
|---|---|---|
| Microsoft Authenticator | enabled, number matching required | ☐ |
| SMS / voice | disabled where the tenant allows | ☐ |
| Temporary Access Pass | enabled for onboarding; single use, short lifetime | ☐ |

## 10. Access review *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Scope | every department in scope, one sheet/section per department | ☐ |
| Columns | user → groups → resources → last logon → manager → Keep/Remove/Change | ☐ |
| Sign-off | department head, dated; the sheet is unsigned until the review happens | ☐ |
| Action tracking | `business/p2-access-review-pack.md` — item, owner, due date, status, evidence link | ☐ |
| Closure proof | re-export after processing the agreed removals | ☐ |

## 11. Known gaps and exceptions

| Item | Note |
|---|---|
| Cloud work needs the 30-day M365 trial | Started deliberately at Phase 3 so the window covers Cloud Sync, CA and ScubaGear. If it lapses, the fallback is Entra ID Free with Security Defaults and Conditional Access is documented, not pretended. |
| Cloud Sync agent is a GUI install | The agent installation is a wizard; everything around it (scope, UPNS, exclusions) is scripted and the install is a runbook step with a screenshot. |
| Mover removal is limited to managed role groups | The engine only removes role groups it knows about from `configs/role-matrix.csv`. Groups that represent a separate approval (for example a project distribution list) are left alone and reported. This is a safety choice, documented rather than implicit. |
| `lastLogonTimestamp` accuracy | It replicates within about 14 days, which is accurate enough for a 90-day stale-account rule and is noted so the report is not over-trusted. |
| Break-glass monitoring | The sign-in alert on the break-glass accounts is set up here and watched from P7 (Wazuh); until then it is a manual review item. |
