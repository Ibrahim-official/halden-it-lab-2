# P5 — Phase 0: Design document (design before you build)

**Project:** P5 Risk-Based Patch and Vulnerability Management Program
**Company:** Halden Distribution Ltd. (fictional, 85 users) · **Domain:** `ad.halden.internal`
**Status:** Phase 0 complete · **Owner:** Muhammad Ibrahim Akmal · **Mode:** A (Advisor)
**Spec:** [`docs/plan/P05-patch-vulnerability-management.md`](../../../docs/plan/P05-patch-vulnerability-management.md)

> Why design first: a vulnerability management programme is a *decision model*, not a scanner. The
> scanner produces a list; the model decides what the business will actually fix this week, who owns
> it and how you prove it is done. Getting the tiers, the SLAs and the closure rule written down
> before any scan runs is what stops the programme becoming "the scanner said 400 criticals, so we
> patched everything and broke payroll". It also gives interview answers about *why*, not just *what*.

---

## 1. Goal and scope

Build a patch and vulnerability management programme that a two-person IT team could actually run:

- **Ring-based Windows patching** (WSUS with client-side targeting through Group Policy)
- **Automated Linux patching** (Ansible, one host at a time, with pre/post health checks)
- **Weekly authenticated vulnerability scanning** (Greenbone Community Edition on LNX01)
- **A risk-based prioritisation engine** (`scripts/05-prioritize.py`) that enriches findings with
  CISA KEV, FIRST EPSS, exposure and asset criticality and produces a P0–P4 work list
- **A closure loop**: a ticket is only closed when a rescan shows the finding is gone
- **Management reporting**: tier distribution, KEV exposure, SLA targets, MTTR once measured

Out of scope for P5: fixing the findings themselves across every project (some are remediated here
as worked examples, the rest are handled by their owning project — endpoint hardening in P4, network
segmentation in P6, backup immutability in P8). P5 *finds* and *prioritises*; the portfolio's other
projects provide the controls.

## 2. Business context (why this exists)

Halden patches when someone has time. Nobody knows which machines are missing which updates, the
firewall firmware is two years old, and a scan by the cyber-insurance provider came back with 400
"critical" findings. IT cannot fix 400 things, and management cannot tell which ones matter.

**Market evidence that shapes the design** (from `docs/plan/00-research-and-selection.md`):

- Exploitation of vulnerabilities as an initial access vector **rose 34%**, concentrated on **edge
  devices and VPNs** (Verizon DBIR 2025). That is why FW01 (the edge device) is treated as an
  internet-exposed asset even inside an isolated lab.
- **CISA BOD 26-04 (June 2026)** replaced flat patch deadlines with risk tiers based on public
  exposure, KEV status, whether exploitation can be automated, and technical impact. The design
  below is **inspired by** that model rather than a copy of it, and says so.
- CVSS alone overwhelms small teams. Prioritising on **known exploitation (KEV)** and **exploit
  likelihood (EPSS)** concentrates effort on the small share of CVEs that attackers actually use.

**Success = the measurable criteria** in the P5 plan: three patch rings, automated Linux patching,
weekly authenticated scans, every finding enriched and tiered with an SLA date, a remediation
dashboard, and a written policy with an exception process.

## 3. The prioritisation model (the core of this project)

### 3.1 Why raw scanner counts are useless

A scanner reports **everything that is different from a reference**, weighted by severity. It does
not know:

- whether anyone is actually exploiting the flaw (most high-CVSS CVEs are never used);
- whether the asset is reachable by an attacker or is sitting behind two firewalls;
- whether the business would care if the asset fell over.

So the raw number is a *workload*, not a *risk*. "400 criticals" is a true statement and a useless
plan. The model below converts it into a small, ranked list of things that matter, and an explicit
decision (accept / schedule / fix now) for everything else.

### 3.2 The tier rules (first match wins)

Implemented by the pure function `tier()` in `scripts/05-prioritize.py`; mirrored in
`configs/p05-tier-rules.yml` and, for the browser demo, in `demo/prioritizer.js`.

| Tier | Rule (all data-driven) | Remediation SLA (target) |
|---|---|---|
| **P0 — Emergency** | In **KEV** *and* the asset is **internet-exposed** | **3 days**, plus a compromise check before and after patching |
| **P1 — Critical** | In **KEV** (internal), *or* EPSS ≥ 0.5 on an exposed asset | 7 days |
| **P2 — High** | EPSS ≥ 0.1, *or* CVSS ≥ 9.0 on a criticality-3 asset | 30 days |
| **P3 — Medium** | CVSS ≥ 7.0 | 60 days |
| **P4 — Low** | Everything else | Next maintenance cycle / upgrade |

The order is the model. A known-exploited flaw on a reachable host jumps the queue regardless of
CVSS, because "someone is using this in the wild right now" beats any estimate of severity. A
CVSS-10 flaw on a rebuildable workstation that nobody has ever exploited is P3 or P4 — not because
it is unimportant, but because ten P0s are worse than one.

### 3.3 The priority score (ranking inside a tier)

Tiers decide *when*. Within a tier, a 0–100 score decides *order*:

```
score = 40·KEV + 25·EPSS + 15·InternetExposed + 12·(CVSS/10) + 8·((criticality−1)/2) + 5·Ransomware
```

- **KEV (40)** — the single strongest signal: exploitation is confirmed, not predicted.
- **EPSS (25)** — scaled probability, so a 0.9 outranks a 0.2 within the same tier.
- **Exposure (15)** — an internet-facing box is reachable without a foothold.
- **CVSS (12)** — still counted, but deliberately the *smallest* severity weight.
- **Criticality (8)** — 1 → 0, 2 → 4, 3 → 8. Business impact matters, but it is not a substitute
  for exploitability.
- **Ransomware bonus (5)** — KEV entries linked to known ransomware campaigns, because Halden's
  realistic worst day is a ransomware day.

The weights sum to 105 before the cap, so a perfect finding scores 100. That is intentional: the
score is a ranking device, not a currency.

### 3.4 The funnel

```
   N findings from the scanner
        │  deduplicate      (same host + CVE + service + port = one task, not two)
        ▼
   N' unique findings
        │  enrich           (KEV, EPSS)   join assets (exposure, criticality)
        ▼
   tiered work list: P0 / P1 / P2 / P3 / P4
        │  P0+P1 only
        ▼
   tickets  →  patched  →  rescan  →  verified closed (ticket may now close)
```

The funnel is the project's headline visual (`docs/diagrams/p05-architecture.svg`) and the answer
to "our scanner says 4,000 vulnerabilities — what do you do Monday morning?".

## 4. Patch rings (Windows) and the Linux cycle

### 4.1 Why rings

A flat rollout means a bad update reaches every machine before anyone notices. Rings turn "patch
everything" into a controlled experiment:

| Ring | Scope | Deadline | Approval |
|---|---|---|---|
| `Ring0-Pilot` | 2 pilot workstations | 2 days | Automatic for security/critical |
| `Ring1-Broad` | Remaining workstations | 5 days | Manual, only after the pilot is healthy |
| `Ring2-Servers` | Member servers | 14 days, in the Saturday window | Manual, after both workstation rings |

Definitions are in `configs/p05-patch-rings.csv`; the GPOs are created by
`scripts/09-Invoke-WsusRingSetup.ps1`; the pilot gate is enforced in code by
`scripts/10-Approve-WsusUpdates.ps1` (default: ≥ 90% of the pilot installed, otherwise broader
approval is refused).

**Domain controllers are deliberately not in a ring.** DC02 is patched first, its health is checked
(`dcdiag`, replication, services), and only then DC01. Patching both at once is how a small company
loses its domain for an afternoon. This is a documented design decision, not an oversight.

### 4.2 Linux

`scripts/13-patch-linux.yml` runs with `serial: 1`: pre-check (free space), update, reboot only if
`/var/run/reboot-required` exists, then assert SSH is running and record the kernel before and after.
`unattended-upgrades` is the safety net for security-only updates between monthly cycles. Because
patching is automated, the *decision* remains human: the playbook is dry-run first
(`--check`), and a failure stops the run rather than patching the next host.

## 5. The closure loop (why a ticket cannot be closed by opinion)

```
finding (tier, due date)  →  ticket (owner, SLA)  →  remediation (patch/config/compensating)
        ▲                                                          │
        └────────────  verification rescan  ←──────────────────────┘
                       (07-verify-closure.sh)
```

`scripts/07-verify-closure.sh` compares the work list from the scan that opened the tickets with the
work list from the verification scan, and reports closed / still-open / new. **MTTR is derived from
those two files, never estimated.** That is the difference between a remediation programme and a
spreadsheet of good intentions.

## 6. Roles, maintenance windows and exceptions

| Decision | Owner | Notes |
|---|---|---|
| Remediate the finding | IT (technical) | Patch, config change, or documented compensating control |
| Approve downtime for a server | Asset owner (business) | Servers patch in the Saturday 22:00 window |
| Accept the residual risk | Management | Signs the exception, with a compensating control and an expiry ≤ 90 days |
| Emergency change for a P0 | IT, notifying the business immediately | No waiting for the monthly CAB; a change record is raised after the fact |

An exception is not "we did nothing". It means a named business owner accepted a stated risk, a
compensating control is in place, and the exception has an expiry date. The register is
`business/p05-exception-register.md` and the standard is `business/p05-patch-vuln-policy.md`.

## 7. Architecture

See `docs/diagrams/p05-architecture.svg` (also the portfolio hero image) and
`docs/diagrams/p05-architecture.drawio` (editable source). In words:

- **Data sources on the left**: PTuesday/vendor PSIRT feeds, CISA KEV, FIRST EPSS, the scanner, the
  P9 asset CMDB.
- **Human decision points** in the middle: pilot gate approval, triage of a new critical finding,
  risk acceptance for anything that cannot be fixed in time.
- **Outputs on the right**: the tiered work list, service-desk tickets, verification, and the
  monthly report to management.

## 8. Honest limitations of scanning a home lab

The portfolio must not overstate what a lab can prove:

1. **Scale.** Ten hosts is not 400 endpoints. The *method* scales; the *numbers* do not. Any
   percentage here describes the sample or the lab, never a real fleet.
2. **Traffic.** The lab's "internet-exposed" hosts are exposed only in the design sense (FW01 faces
   the WAN, LNX01 publishes a service through it). Inside the isolated lab nothing is reachable from
   the internet, so exposure drives *priority*, not real attack surface.
3. **Feeds.** KEV and EPSS are real public feeds; in this build kit they are exercised offline
   against a **synthetic stand-in** so the prioritizer demo needs no network. The live run fetches
   the real feeds.
4. **Time.** MTTR, SLA achievement and patch compliance are trends that need weeks of real cycles.
   Until they exist they are reported as **not measured** — never estimated (AGENTS.md rule R2).
5. **Seeding.** Some findings are deliberately seeded in the lab (an unpatched snapshot, a pinned
   outdated package, SMBv1 on a test box) so the first report has something to prioritise. Every
   one of those is labelled as lab seeding wherever it appears.

## 9. Snapshot and rollback plan

- **Before every phase:** snapshot each VM the phase touches, named `snap-p5-ph<N>-before`
  (e.g. `snap-p5-ph1-before`, `snap-p5-ph3-before` for LNX01).
- **Rollback:** revert the snapshot. WSUS/GPO changes are removed by deleting the GPOs; the scanner
  stack is removed with `docker compose down` plus `/opt/greenbone`; a bad update is uninstalled from
  the pilot ring. Domain controllers are fixed forward where possible.
- Phase 0 changed nothing in the lab, so no snapshot was needed. **Phase 1 does change things.**

## 10. Risks

| Risk | Mitigation |
|---|---|
| The scanner probing something outside the lab | Hard range guard in `scripts/lib/labguard.sh` and a per-address check in `02-setup-targets.sh`; a public address aborts the run |
| A bad patch reaching every machine | Three rings with a coded pilot gate (≥ 90%) before broader approval |
| Both DCs patched at once, losing the domain | Fixed order DC02 → DC01 with post-checks; the script stops on the first failure |
| WSUS database bloat, clients failing to check in | Monthly maintenance script (`12-Invoke-WsusMaintenance.ps1`) |
| Tickets closed without proof | `07-verify-closure.sh`; the closure rule is stated in the policy and the ticket template |
| Chasing CVSS instead of real risk | The tier model is KEV/EPSS/exposure first; the report shows the funnel |
| Publishing a number that was never measured | Every results table says "not measured" until a real run produces the source file |

## 11. Interview notes (phase 0)

**"Your scanner shows 400 criticals. What do you do Monday morning?"** Not fix 400 things. First
check whether any are known-exploited (KEV) on an internet-facing host — those are the only
emergencies. Then rank what is left by EPSS (will it actually be used?), exposure and asset
criticality. Take the top few into this week's window, ticket them with a due date and an owner, and
schedule the rest into cycles by tier. Show the funnel: how many findings went in and how many
urgent actions came out.

**"How do you set SLA targets you can meet?"** Start from what the team can absorb (two days of
work a month here), assign the short deadlines only to the tiers that justify interrupting other
work, and record the target in the policy the business signs. Then report *achievement* honestly —
"four of six P1s inside 7 days" is a credible sentence; claiming 100% is not.

**"Why do exposure and asset criticality change the priority?"** A CVSS-10 flaw on a machine nobody
can reach and nobody has exploited is a maintenance task. The same flaw on a firewall reachable from
the internet, or on the domain controller everything depends on, is an emergency. CVSS measures the
flaw; exposure and criticality measure the risk to *this* business.

**"What changed in 2026?"** CISA BOD 26-04 moved from one deadline for everything to risk tiers, and
added a compromise check on exposed, exploited assets *before* patching — because if an attacker is
already inside, patching the door does not remove them.

---

*Next step: Phase 0 policy, then Phase 1 (WSUS rings, snapshot first). Mode A: the owner runs the
scripts and pastes output back; nothing in the lab has been executed yet.*
