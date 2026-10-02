---
id: p08
order: 6
title: Backup, Recovery and Disaster Recovery with Automated Restore Verification
tagline: 3-2-1-1-0 backups with an immutable copy and restore tests that actually run every week
status: in-progress
started: 2026-10-02
roles:
  - sysadmin
  - it-support
skills:
  - Proxmox Backup Server
  - Veeam CE
  - restic
  - MinIO Object Lock
  - wbadmin
  - S3 Object Lock
  - Business Impact Analysis
  - RTO/RPO
  - DR Runbooks
  - AD Recycle Bin
  - authoritative restore
  - Bash
  - PowerShell
  - Python
  - Uptime Kuma
jd_bullets:
  - Maintain backup, recovery and disaster-recovery procedures and periodically verify backups
  - Work with different departments (business impact analysis)
  - Technical documentation; vendor coordination (offsite storage)
  - Understand business operations and prepare reports and presentations for management
hero: ./evidence/public/p08-architecture.svg
documents:
  - title: "Backup Policy"
    href: ./business/p08-backup-policy.pdf
  - title: "Change Record"
    href: ./business/p08-change-record.pdf
  - title: "Dr Plan"
    href: ./business/p08-dr-plan.pdf
  - title: "Executive Brief"
    href: ./business/p08-executive-brief.pdf
  - title: "Restore Test Register"
    href: ./business/p08-restore-test-register.pdf
  - title: "Service Levels"
    href: ./business/p08-service-levels.pdf
repo_path: projects/p08-backup-dr
cv_bullets:
  - Led a Business Impact Analysis with five departments to define recovery time and data-loss objectives per system,
    then designed a 3-2-1-1-0 backup strategy with a non-domain-joined, hardened backup server and an immutable off-site
    copy.
  - Proved immutability by attempting to destroy the off-site repository with the backup account's own credentials and
    recording the refused deletion and the successful version-rewind recovery.
  - Built an automated weekly restore verification (hash-checked file restores plus a sandboxed virtual-machine boot
    with service health checks) whose result is published to monitoring and forms the backup KPI.
lab_note: "Home-lab project in an isolated, simulated 85-user company (Halden Distribution Ltd.). This page shows a
  working build kit that is being executed in the lab phase by phase. Recovery times, restore success rates and drill
  durations are deliberately absent: they appear only once a timed drill has actually measured them. Until then every
  figure here is a target, clearly labelled as such."
---

## The problem

Halden "has backups": a nightly copy of the file server to a USB disk plugged into the same server,
running under a Domain Admin account, never tested — and the domain controllers are not backed up at
all. That is worse than having nothing, because it creates false confidence. Attackers now target the
backups themselves: industry research finds backup repositories attacked in around **96% of ransomware
attacks** and successfully destroyed in about **76%** of those attempts, and ransomware appears in
**88% of SMB breaches** (Verizon DBIR 2025). A domain-joined, on-line-only, untested backup sits
squarely in that majority. (The job-ad and market evidence behind this project is summarised in
`docs/plan/00-research-and-selection.md`.)

## What I built

- **A Business Impact Analysis with each department** that converts "how long can you survive without
  this?" into recovery objectives per system — the business sets the targets, IT engineers to them.
- **A 3-2-1-1-0 design**: three copies, two media, one off-site, one immutable or offline, and zero
  errors on a verified restore as the standard the whole design is held to.
- **A hardened backup server that is not part of the domain**, with its own credentials, console TOTP,
  a host firewall limited to the backup ports, and an encrypted repository — so a compromised domain
  does not take the backups with it.
- **Three layers of backup**: whole virtual machines per tier, hourly file incrementals for the
  critical shares, and an AD-aware system-state backup that is what makes a proper directory restore
  possible.
- **An immutable off-site copy** in S3-compatible object storage with a deletion lock, plus a monthly
  **offline** encrypted disk that no network credential can reach.
- **Automated weekly restore verification** — files restored and hash-compared, the repository
  integrity-checked, and one virtual machine per week booted in an isolated sandbox with service health
  checks — with the result pushed to monitoring and a failure raised as an alert.
- **Active Directory recovery drills** (recycle-bin restore and an authoritative restore in a sandbox)
  and a **timed ransomware recovery drill** against the agreed targets.
- **Documentation someone else can use**: a DR runbook written for a person who did not build the lab,
  a restore-test register, a backup policy, a change record and a management brief.

## How it works

![P8 backup and DR data flow](./evidence/public/p08-architecture.svg)

Production servers are copied nightly to an encrypted repository on the backup server, which is
deliberately **not domain-joined** and lives in the management network. A second copy is synchronised
to an object store configured with a deletion lock; a third is rotated monthly to an offline encrypted
disk. The weekly restore test sits on top of the whole chain and is the "0" in 3-2-1-1-0 — the design
counts as finished only when a restore has been proven, automatically, week after week.

The immutability is not a promise in a policy; it is a test that is *expected to fail*. The check runs
with the backup user's own credentials and records the refusal:

```bash
# 1. this "succeeds" - but only writes a delete marker
mc rm --recursive --force halden/backup-immutable/fs01
# 2. this MUST fail - the locked object versions are WORM-protected
mc rm --recursive --force --versions halden/backup-immutable/fs01
# 3. this MUST fail too - compliance retention cannot be cleared or shortened, even by root
mc retention clear --recursive halden/backup-immutable/fs01
```

Because deletion lock requires versioning, restic keeps working normally and the locked versions
survive the "delete" — which is exactly why the lock period must be at least the recovery window
promised to the business.

## Results

**Not measured yet.** The build kit (scripts, configurations, runbooks, business artifacts) is complete
and the lab execution is beginning. There is deliberately **no measured recovery time, no restore
success rate and no drill duration on this page** — those numbers appear only once a timed drill has
actually produced them, each with a file in `evidence/public/` as its source. What exists today is the
agreed **targets** (a two-hour recovery objective for identity, four hours for file services and the
order system, one hour of acceptable data loss on critical data) and the machinery that will hold the
design to them.

| Metric | Before | After | Source |
|---|---|---|---|
| Immutable copy: deletion attempt with backup credentials | not measured | not measured | pending |
| Weekly restore test: files hash-matched | not measured | not measured | pending |
| Recovery time vs target (per system) | not measured | not measured | pending |

## Business side

The technical work is only half of a resilience project; the other half is what the business receives
and signs off:

- **Executive brief** — what Halden can survive, expressed as targets and labelled as targets, with
  the honest "proven or not" position stated against every claim.
- **Backup and recovery policy** — scope, tiers, the 3-2-1-1-0 rule, retention, encryption and key
  escrow, access control and the verification schedule. A draft, visibly unsigned.
- **Disaster recovery plan** — roles, contact steps, the order of restoration, and the decision points
  (restore in place or rebuild; which restore point; when to accept data loss). Untested until a drill
  is run, and it says so.
- **Service levels** — the recovery objectives agreed with each department, including the cost/risk
  trade-off the business is accepting and an explicitly empty "latest measured" column.
- **Restore-test register** — the format that proves backups are periodically verified, with empty rows
  rather than invented successes.
- **Change record** — risk, test plan and backout in the shape a small company's change log expects,
  feeding the governance dashboard in P10.

## What I learned / what I'd do differently

- **The plan's default tool assumed a different hypervisor than the lab actually has.** P1 chose
  Hyper-V, so a Proxmox-specific backup product could not be the default; I designed a hypervisor-
  agnostic core and kept the alternatives documented. Designing for the lab you have beats following a
  plan literally.
- **A policy nobody tests can be quietly wrong.** The first draft of the retention table promised the
  business a 30-day recovery window but only kept four weeks for one tier. A small unit test on the
  retention calculator caught it — the same lesson as P1's permission audit: an unautomated control is
  a wish, not a control.
- **It is tempting to measure the backup instead of the restore.** "The job ran" is comfortable and
  meaningless. The only number that matters to a director is how long until we are working again — so
  the KPI here is a weekly restore test and a timed drill, and even the immutability evidence is a
  *failed* deletion.
- **Keeping the backup out of the domain has a real cost, and that is the point.** It means another set
  of credentials and no single sign-on. It buys survival of the exact scenario backups exist for, and
  pretending otherwise would have been the easy mistake.
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
