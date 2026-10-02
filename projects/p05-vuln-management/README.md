# P5: Risk-Based Patch and Vulnerability Management Program

> Home-lab project in an isolated, simulated 85-user company ("Halden Distribution Ltd.").
> Presented as a home lab on the portfolio site — never as employment experience.
> Scanner targets are limited to the **lab ranges only** (192.168.10.0/24, 192.168.20.0/24,
> 192.168.30.0/24) and the bundled sample data is **synthetic** (see [`data/README.md`](./data/README.md)).

**Status:** build kit complete — **lab execution pending** · **Build order:** 7 of 10 · **Depends on:** P1, P4 (P9 CMDB criticality improves it later)
**Plan:** [`docs/plan/P05-patch-vulnerability-management.md`](../../docs/plan/P05-patch-vulnerability-management.md) · **Design:** [`docs/00-design.md`](./docs/00-design.md) · **Site page source:** [`showcase.md`](./showcase.md) · **Progress:** [`PROGRESS.md`](../../PROGRESS.md)

## Problem

Halden patches "when someone has time". Nobody knows which machines are missing which updates, the
firewall firmware is two years old, and a scan by the cyber-insurance provider returned 400
"critical" findings. IT cannot fix 400 things, and management cannot tell which ones matter. CVSS
alone makes that worse: it flags a flaw nobody has ever exploited on a spare laptop with the same
urgency as a known-exploited flaw on the firewall, so the list stays long and the real risks stay
open. Exploitation of vulnerabilities as an initial access vector rose 34% and is concentrated on
edge devices and VPNs — exactly the kind of device an SMB leaves unpatched longest.

## What I built

- **A Python prioritisation engine (`scripts/05-prioritize.py`)** that ingests a scanner export and
  an asset-criticality inventory, enriches every finding with **CISA KEV** (known-exploited) and
  **FIRST EPSS** (exploit probability) data, joins exposure and criticality, and produces a tiered
  P0–P4 work list with an SLA date and a 0–100 priority score. Standard library only, `argparse`
  subcommands, a `--dry-run`, structured logging, and **26 unit tests** over the pure scoring core.
- **A documented, testable risk model.** `tier()` is a pure function with a fixed rule order, so
  "why is this a P1?" has one auditable answer. The model is inspired by the risk-tier approach in
  **CISA BOD 26-04** (published June 2026): exposure and confirmed exploitation outrank raw severity.
- **Ring-based Windows patching** — WSUS with client-side targeting through Group Policy, three rings
  (Pilot → Broad → Servers), a coded **pilot gate** that refuses broader approval until the pilot is
  healthy, monthly WSUS hygiene, and a server patch script that patches **DC02 then DC01, never
  together**, with pre- and post-checks.
- **Automated Linux patching** with an Ansible playbook that runs one host at a time, reboots only
  when needed, and asserts SSH is healthy afterwards — with unattended security updates between cycles.
- **Weekly authenticated scanning** with Greenbone Community Edition on LNX01, behind a hard
  **lab-range safety guard**: a wrong address aborts the run rather than scanning it.
- **A closure loop** — P0/P1 items become service-desk tickets (P9 hand-off), and a ticket only
  closes when a re-scan no longer reports the finding; MTTR is derived from the two scans, never estimated.
- **An interactive browser demo** (`demo/index.html`) that runs the same model over a bundled
  **synthetic** sample with no backend and no network, so a reviewer can watch findings collapse into
  a short urgent list.
- **The business layer**: a patch and vulnerability policy with **targets** rather than slogans, an
  exception/risk-acceptance register, a monthly report template, a vendor advisory log, a one-page
  executive brief and a change record.

## Architecture

![P5 risk-based vulnerability prioritisation funnel](docs/diagrams/p05-architecture.svg)

Findings flow in from the left, are deduplicated and risk-scored, and come out as a much shorter
tiered list: ticket → patch → verified closure. Human decision points (the pilot gate, accept-or-fix)
are marked because the model prioritises work; it does not authorise downtime or accept risk.

The heart of the project is the tier rule, and it is deliberately four lines of readable logic
(`scripts/05-prioritize.py`):

```python
def tier(in_kev, exposed, epss, cvss, criticality, rules=DEFAULT_RULES):
    if in_kev and exposed:                                      return "P0"
    if in_kev or (exposed and epss >= rules.epss_critical):     return "P1"
    if epss >= rules.epss_high or (cvss >= rules.cvss_critical and criticality >= 3): return "P2"
    if cvss >= rules.cvss_high:                                 return "P3"
    return "P4"
```

## How to reproduce

Run in order. Every shell and Python script is lab-guarded and every PowerShell script supports
`-WhatIf` (see [`docs/runbooks/`](./docs/runbooks/)).

| Order | Where | Script | Does |
|---|---|---|---|
| 1 | LNX01 | `scripts/00-deploy-scanner.sh` | Deploys Greenbone CE in Docker; admin password shown once, never stored |
| 2 | LNX01 | `scripts/01-harden-scanner.sh` | Creates the least-privilege scan key; SSHs the UI to loopback; host firewall |
| 3 | LNX01 | `scripts/02-setup-targets.sh` | Creates scan target sets from the scope file after per-address lab-range validation |
| 4 | LNX01 | `scripts/03-schedule-scan.sh` | Weekly Sunday 02:00 scan plus the monthly post-patch verification scan |
| 5 | LNX01 | `scripts/04-export-report.sh` | Exports the newest finished report to `data/scans/latest.csv` (+ XML archive) |
| 6 | LNX01 | `scripts/05-prioritize.py` | The engine: deduplicate → enrich → tier → score → work list (CSV/JSON, `--dry-run`) |
| 7 | OPS01 | `scripts/06-create-tickets.sh` | Creates GLPI tickets for P0/P1 only, with the owner and due date (P9 hand-off) |
| 8 | any | `scripts/07-verify-closure.sh` | Compares before/after scans to prove closure; writes the closure report |
| 9 | WSUS host | `scripts/09-Invoke-WsusRingSetup.ps1` | Creates the three rings, client-side-targeting GPOs and approval rules |
| 10 | WSUS host | `scripts/10-Approve-WsusUpdates.ps1` | Approves the broader rings only after the pilot gate (≥ 90%) passes |
| 11 | WSUS host | `scripts/11-Invoke-ServerPatch.ps1` | Patches servers in DC02→DC01→FS01 order with pre/post health checks |
| 12 | WSUS host | `scripts/12-Invoke-WsusMaintenance.ps1` | Monthly WSUS hygiene: decline superseded/expired, run cleanup |
| 13 | LNX01 | `scripts/13-patch-linux.yml` | Ansible Linux patching, one host at a time, with pre/post checks |
| 14 | any | `scripts/14-weekly-report.sh` | Weekly/monthly status report from the work list and closure report |

**Prerequisites:** P1 complete (so `ad.halden.internal` and the Windows hosts exist), the LNX01 VM
present, Docker available on LNX01, and a member server able to host the WSUS role. The scanner's
admin password and the GLPI API tokens are entered at a prompt or read from the environment and
stored in the owner's password manager — never in the repository.

**The lab-range safety guard (AGENTS.md rule R1).** The scanner is the one tool here that actively
probes hosts, so it is guarded twice: `scripts/lib/labguard.sh` validates **every** target against
the three Halden ranges and aborts on anything else, and `scripts/02-setup-targets.sh` re-validates
the whole scope file before creating a target. There is no override — a public address, a home-router
address or an employer's system is refused, not warned about. You can see the refusal yourself:

```bash
bash -c '. scripts/lib/labguard.sh; require_lab_target 127.0.0.1'
# ERROR: target '127.0.0.1' is outside the Halden lab ranges (...). Refusing to scan. AGENTS.md rule R1.
```

**Snapshot before every phase** (`snap-p5-ph<N>-before`). **Rollback:** revert the snapshot, delete
the phase's artefacts (update GPOs/rings, `/opt/greenbone`, unapproved WSUS updates), or restore the
firewall configuration from its pre-change backup. Domain controllers are fixed forward where possible.

## Results

**Not measured yet.** This build kit has been written but not executed in the lab, so this table is
deliberately empty rather than filled with plausible-looking numbers. The one figure that appears
anywhere is a property of the **synthetic sample** the demo runs on (51 rows → 49 unique → 9 urgent),
and it is labelled as such wherever it appears.

| Metric | Before | After | Source |
|---|---|---|---|
| Scanner findings (raw → after deduplication) | not measured | not measured | — |
| Findings in the urgent queue (P0 + P1), and their share | not measured | not measured | — |
| Findings matched to CISA KEV, and how many were on exposed assets | not measured | not measured | — |
| Authenticated vs unauthenticated finding count (the 5–10× claim) | not measured | not measured | — |
| Patch compliance within the ring deadline (workstations, servers) | not measured | not measured | — |
| P0 remediated within 3 days | not measured | not measured | — |
| Mean time to remediate (MTTR) by tier | not measured | not measured | — |
| Findings closed only after a verification rescan | not measured | not measured | — |

## Acceptance tests

| Test | Expected | Actual | Pass |
|---|---|---|---|
| Validate a scope file containing a deliberately wrong address | The lab guard aborts and scans nothing | not run | ☐ |
| Approve a security update while the pilot ring is below the gate | Approval is refused | not run | ☐ |
| Patch DC02 and fail its post-check | DC01 is not patched | not run | ☐ |
| Run the prioritizer over a scan export | Every finding has a tier, an SLA date and a score | not run | ☐ |
| Run the prioritizer twice over the same input | Identical output (deterministic) | not run | ☐ |
| Attempt to close a P0 ticket without a verification scan | Not permitted by the process | not run | ☐ |
| Run the Linux playbook in check mode | No changes reported as made | not run | ☐ |
| Re-run the ring setup script | Idempotent: no duplicate groups, GPOs or links | not run | ☐ |
| Python unit tests (`scripts/tests/test_prioritize.py`) | All pass (26 tests over the pure scoring core) | 26 passed locally | ☑ |
| Regenerate the synthetic sample with the generators | Byte-identical files; row counts match `data/README.md` | 51 rows / 10 assets / 17 CVEs | ☑ |

*The two ticked rows are tooling checks that run without the lab (and run today); they are not lab
results. Every row that needs a VM stays unticked until the phase runs.*

## Business deliverables

| Artifact | For | File |
|---|---|---|
| Executive brief: why "fix everything by Friday" is not a plan | Management | `business/p05-exec-brief.md` |
| Patch and vulnerability policy (scope, tiers, SLA **targets**, exceptions) | Approval by management | `business/p05-patch-vuln-policy.md` |
| Exception / risk-acceptance register (with a worked example row) | Risk owners | `business/p05-exception-register.md` |
| Monthly patch and vulnerability report template | Management reporting | `business/p05-monthly-report-template.md` |
| Vendor advisory log (firmware PSIRT feeds, applicability, action) | IT / vendor coordination | `business/p05-vendor-advisory-log.md` |
| Change record (programme build **and** a worked P0 remediation record) | Change log / audit (P10) | `business/p05-change-record.md` |

## The interactive demo

`demo/index.html` runs the prioritisation model entirely in the browser over the bundled synthetic
sample — no backend, no network calls, no tracking. Open the file directly, or serve the folder
(`python3 -m http.server`). It shows the funnel (49 findings in → 9 urgent out), the tier distribution,
the ranked table with the reason each finding got its priority, and live filters. The banner states
plainly that the data is synthetic, and the model in `demo/prioritizer.js` mirrors the Python rules
and thresholds (verified to produce identical counts: 2 / 7 / 17 / 10 / 13).

## Lessons learned

- **A scanner output is a workload, not a plan.** Half of this project was resisting the urge to
  start patching; the useful work was writing the rule that decides what *not* to do this week.
- **The guard is part of the feature.** A tool that probes hosts is only safe if it refuses to run
  outside the lab, so the lab-range check went in first and is testable on its own.
- **Pure functions are the cheapest quality win.** Keeping `tier()` free of I/O made all 26 tests
  possible without a network, a scanner or a single lab host — so the model is verified before
  anything is risked in the lab.
- **Honesty is a design constraint, not a disclaimer.** Every table says "not measured" and MTTR is
  explicitly withheld because one scan cannot produce it. A prioritisation project that invented its
  own effectiveness numbers would be the worst possible demonstration of risk discipline.
- **What I would do differently:** start the greenbone feed sync the day before (it takes hours), and
  define the asset criticality mapping with the business earlier — the tier model is only as good as
  the criticality data underneath it, which is exactly why P9's CMDB improves this project later.

## Interview notes

**"Our scanner says 4,000 vulnerabilities — what do you do Monday morning?"** Nothing dramatic. First
I filter for the two things that make a finding an emergency: is it known-exploited (CISA KEV), and is
the asset reachable from outside? Those are the only ones that interrupt today's work, and on an
exposed host I check for compromise *before* patching, because patching the door does not remove an
attacker already inside. Then I rank what is left by EPSS (how likely is it actually used?), exposure
and asset criticality, take the top few into this week's window with an owner and a due date, and
schedule the rest by tier. I keep the raw number, because it is a useful trend line — but it is never
the plan.

**"How do you set SLA targets you can actually meet?"** Start from capacity, not from ambition. Two
people cannot absorb a flood of 3-day deadlines, so only the tiers that justify interrupting other
work get short ones — P0 at 3 days, P1 at 7 — and everything else has a window that matches a real
patch cycle. The targets go in a policy the business signs, and then I report *achievement* honestly:
"four of six P1s inside 7 days" is a credible sentence, "100% compliant" usually is not.

**"Why should exposure and asset criticality change the priority — isn't CVSS enough?"** CVSS scores
the flaw in isolation; it does not know whether anyone can reach the host or whether the business
depends on it. A CVSS-10 bug on a spare laptop nobody has exploited is a maintenance task; the same
bug on the firewall or a domain controller is an emergency. Exposure and criticality turn a severity
score into risk to *this* business, which is the only kind of risk management actually cares about.

**"A patch broke something in the pilot ring — what now?"** The rings exist exactly for this. The
broader approval is gated, so the fault is contained to two machines. I stop the rollout, roll back or
uninstall in the pilot, confirm the affected service is healthy, raise it with the vendor with the
evidence, and only then decide whether to defer that update or apply a compensating control. What I do
*not* do is push it out and hope — that is the failure the ring design is meant to prevent.

**"How do you know a vulnerability is actually fixed?"** A rescan, not a claim. The ticket stays open
until the scanner stops reporting the finding, and the closure report compares the two scans so
"closed" is a measurement. That is also why MTTR is derived from those two files rather than
estimated — if I cannot point at the source, I do not publish the number.
