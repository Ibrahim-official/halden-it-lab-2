---
id: p03
order: 4
title: Active Directory Security Assessment and Privileged Access Hardening
tagline: Found and closed the paths an attacker would use to take over the domain
status: in-progress
started: 2026-10-02
roles:
  - sysadmin
  - it-support
skills:
  - Active Directory
  - PingCastle
  - Purple Knight
  - BloodHound CE
  - Windows LAPS
  - Protected Users
  - gMSA
  - Kerberos
  - Fine-Grained Password Policies
  - Privileged access tiering
  - Delegation
  - Group Policy
  - PowerShell
  - Python
jd_bullets:
  - System hardening and access controls based on least privilege
  - Identify and respond to vulnerabilities and unauthorized access
  - Perform regular security checks and support remediation
  - Identify operational issues and communicate them to management (risk report)
  - Accounts, groups, permissions and least privilege
hero: ./evidence/public/p03-architecture.svg
documents:
  - title: "Change Record"
    href: ./business/p03-change-record.pdf
  - title: "Exec Summary"
    href: ./business/p03-exec-summary.pdf
  - title: "Findings Register"
    href: ./business/p03-findings-register.pdf
  - title: "Management Deck"
    href: ./business/p03-management-deck.pdf
  - title: "Privileged Access Policy"
    href: ./business/p03-privileged-access-policy.pdf
repo_path: projects/p03-ad-security
cv_bullets:
  - Audited an Active Directory environment with PingCastle, Purple Knight and BloodHound CE, producing a risk-rated
    findings register where every finding carries a likelihood and impact score, an owner and an evidence file.
  - Implemented a three-tier privileged access model with separate admin accounts, Group Policy logon restrictions,
    Protected Users and delegated helpdesk rights, removing daily-use accounts from Domain Admins.
  - Deployed Windows LAPS with encrypted Active Directory backup and tier-delegated read access, and replaced a legacy
    service account with a gMSA, removing Kerberoasting exposure.
lab_note: Home-lab project in an isolated, simulated 85-user company (Halden Distribution Ltd.). The weaknesses assessed
  here were deliberately seeded in the lab so the assessment had realistic problems to find, and the assessment was run
  as an authorised exercise against the owner's own isolated lab domain only. Every number published on this page comes
  from a real run in the lab; none has been published yet.
---

## The problem

Halden has one shared local administrator password on every workstation, four people in Domain
Admins including one disabled account, service accounts whose passwords have not changed in years, an
unconstrained delegation flag left on the file server, and a domain that still accepts legacy
authentication with a seven-character password policy. Any of those alone is a finding; together they
mean one phished laptop can plausibly reach domain control in hours. That matters because credential
abuse is the most common initial access vector — 22% of breaches in Verizon's 2025 DBIR — and
ransomware appears in 88% of SMB breaches, with attackers escalating to directory control first
because that is what lets them encrypt every machine at once. Halden also cannot answer the simple
business question "who can change the domain?".

## What I built

- **A repeatable assessment** — PingCastle, Purple Knight and BloodHound Community Edition run
  against the lab domain, with the baseline captured before any change and the same tools re-run
  afterwards, so the before/after comparison is like-for-like.
- **A risk-rated findings register** — every finding scored by likelihood × impact (1–25), banded
  P0–P3, with an owner, a target date and an evidence file, produced by a small Python tool whose
  scoring logic is covered by unit tests.
- **Honest seeding of the "before" state** — a lab-guarded, `-WhatIf`-capable script creates the
  realistic weaknesses (Kerberoastable service account, AS-REP-roastable user, unconstrained
  delegation, excess privileged accounts, a shared local admin password, weak policy, legacy
  protocols) so the baseline score means something.
- **Quick wins first** — AD Recycle Bin enabled, Domain Admins reduced to the designed Tier 0
  accounts plus the built-in break-glass Administrator, pre-authentication and delegation weaknesses
  cleared, Print Spooler disabled on the domain controllers, and a stricter fine-grained password
  policy for administrators.
- **Windows LAPS done properly** — schema extension, encrypted Active Directory backup, read access
  delegated by tier (helpdesk on workstations, server admins on servers, Tier 0 on the DCs including
  the DSRM password), 20-character passwords rotating every 30 days, and a post-authentication reset.
- **A three-tier privileged access model** — an `_Admin` OU structure, a separate `adm-t{0,1,2}-*`
  account for every IT person, deny-logon Group Policy per tier, Protected Users for human Tier 0
  accounts, a designated Tier 0 privileged access workstation, and delegated password-reset rights
  for the helpdesk instead of Domain Admin.
- **Service-account and Kerberos hygiene** — a gMSA replacing the legacy service account, Kerberos
  RC4 requests audited before AES-only is enforced, and the krbtgt rotation kept as a separate,
  deliberately non-automated change.
- **Legacy-protocol hardening in an audit-then-enforce sequence** — LM level 5, SMB signing required,
  SMBv1 removed, LDAP signing and channel binding, LLMNR disabled, with NTLM auditing reviewed first.
- **Verification rather than assumption** — a read-only script re-checks every control the project
  claims and reports PASS / FAIL / UNKNOWN, plus a recurring privileged-access review.

## How it works

![P3 tier model and assessment loop](./evidence/public/p03-architecture.svg)

Three tiers, three boundaries. **Tier 0** is the directory itself — the domain controllers and the
privileged access workstation — reachable only by `adm-t0-*` accounts. **Tier 1** is the member
servers and **Tier 2** is the workstations and the helpdesk's work on user objects. The boundaries
are enforced rather than suggested, because deny-logon Group Policy means a Tier 0 account cannot
sign in to a workstation, and a credential that cannot be typed into a workstation cannot be cached
there. Around the tiers runs the loop the project is really about — assess, remediate, detect,
verify, review — with every step producing a file that can be cited.

The idea that makes the model work in a small business is delegation instead of elevation. The
helpdesk does not need domain administrator rights to do its job; it needs the *Reset Password*
extended right on the user organisational units, which the tiering script grants directly:

```powershell
# Reset Password (extended right 00299570-246d-11d0-a768-00aa006e0529) on user OUs only.
$rule = New-Object System.DirectoryServices.ActiveDirectoryAccessRule(
  $sid, [System.DirectoryServices.ActiveDirectoryRights]::ExtendedRight, 'Allow',
  [guid]'00299570-246d-11d0-a768-00aa006e0529')
```

## Results

**Not measured yet.** The build kit is complete — scripts, configs, documentation, business
artifacts and the diagram — and the lab execution has not started, so there is nothing to report.
I am deliberately not publishing numbers before they exist, and the assessment tooling has not been
run: the score, the indicator counts and the attack-path figures are all still open.

| Metric | Before | After | Source |
|---|---|---|---|
| PingCastle global risk score | not measured | not measured | pending |
| BloodHound paths from Domain Users to Domain Admins | not measured | not measured | pending |
| Endpoints with a unique rotating LAPS password | not measured | not measured | pending |
| Findings closed by priority | not measured | not measured | pending |

Each row will be filled from a real lab run, with a file in `evidence/public/` named as its source,
and the same measurement re-taken after remediation so the before/after claim is like-for-like.

## Business side

The technical assessment is only half of it; the other half is what management gets and can act on:

- **One-page executive summary** — the risk in plain language ("one careless click is enough to lose
  the network"), the five things being fixed and when, what is deliberately *not* being done (no
  penetration test, no credential cracking), and the four decisions the business has to make.
- **Findings register** — every finding with a likelihood, an impact, a priority band, a named owner
  and a target date, plus an explicit risk-acceptance log so "we chose not to fix this" is written
  down with an owner and a review date instead of being quietly dropped.
- **Privileged access standard** — the policy behind the technical controls: the tier model, separate
  admin accounts, who may read a LAPS password, service account rules, the break-glass exception and
  the review cycle.
- **Change record** — risk, impact, the phase plan, acceptance tests and the backout plan, including
  the two changes that cannot be reversed (the LAPS schema extension and a krbtgt reset).
- **Five-slide management deck outline** — problem, method, what changed, the score movement, and the
  remaining risks with the asks that go with them.

## What I learned / what I'd do differently

- **Design the scoring before running the tools.** Deciding likelihood × impact and the priority
  bands up front turned the assessment into a decision-ready register rather than a pile of tool
  output, and the same schema is reused later in the portfolio.
- **Authorisation belongs in the code, not in a sentence.** A README that says "lab only" is a
  promise; a gate script that refuses to run without a recorded authorisation reference is a control.
- **Audit, analyse, then enforce is a design decision.** Every protocol change here produces the
  events the enforcement decision rests on. Skipping that would have been faster and would have
  broken something eventually.
- **A tiering model needs a test, not a diagram,** and I would move the privileged access
  workstation's network isolation into this project rather than leaving it to the network phase —
  "privileged access workstation" is not really true while it shares a network with everything else.
> complete; lab execution runs phase by phase. Metrics, diagrams and evidence are published only
> from real runs (the Definition of Done is in `AGENTS.md`, Section 4.7), and progress is tracked
> in `PROGRESS.md`.
> complete; lab execution runs phase by phase. Metrics, diagrams and evidence are published only
> from real runs (the Definition of Done is in `AGENTS.md`, Section 4.7), and progress is tracked
> in `PROGRESS.md`.
> complete; lab execution runs phase by phase. Metrics, diagrams and evidence are published only
> from real runs (the Definition of Done is in `AGENTS.md`, Section 4.7), and progress is tracked
> in `PROGRESS.md`.

> Status: **in progress**. The build kit (scripts, configs, runbooks, business artifacts) is
> complete; lab execution runs phase by phase. Metrics, diagrams and evidence are published only
> from real runs (the Definition of Done is in `AGENTS.md`, Section 4.7), and progress is tracked
> in `PROGRESS.md`.
