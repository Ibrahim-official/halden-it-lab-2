# P10 — Design document (design before build)

**Project:** P10 IT Governance Capstone — CIS Controls v8.1 IG1 scorecard, change control, policy pack
and management reporting
**Company:** Halden Distribution Ltd. (fictional, 85 users) · **Domain:** `ad.halden.internal`
**Status:** build kit complete — **lab execution pending** · **Owner:** Muhammad Ibrahim Akmal ·
**Mode:** A (Advisor)
**Spec:** [`docs/plan/P10-governance-cis-ig1-change-reporting.md`](../../../docs/plan/P10-governance-cis-ig1-change-reporting.md)

> Why governance is the capstone: P1–P9 build things. P10 is the only project that has to answer the
> questions a manager actually asks — *are we secure, are we getting better, what changed and who
> approved it, and what does IT need money for?* Without P10 the other nine are a pile of good
> technical work nobody can see. With it, every number has a source, every change has an approval and
> every gap has an owner.

---

## 1. Goal and scope

Turn nine technical projects into a governed IT function for the fictional Halden by delivering:

- a **CIS Controls v8.1 Implementation Group 1 self-assessment** across all **56 IG1 safeguards**,
  scored before and after, with evidence traced to a named artifact from P1–P9;
- an **ITIL-style change-management process** — standard / normal / emergency, a risk-classified
  RFC, a weekly CAB, a change calendar with freeze periods, and a retrospective for emergencies;
- a **ten-policy IT policy pack** with an acknowledgement process and an exceptions register;
- a **monthly KPI report** and a **risk register / action tracker**, generated from data rather than
  recollection;
- a recorded **"State of IT" talk** with a costed 90-day roadmap.

## 2. Business context (why this exists)

Halden's management cannot answer basic questions. IT work happens but is invisible; changes are
made on a Friday afternoon without telling anyone; there are no written policies, which the
cyber-insurance renewal questionnaire now asks for.

**Market evidence (from `docs/plan/00-research-and-selection.md`):** CIS describes **IG1** — 56
safeguards — as essential cyber hygiene and an emerging minimum standard for every enterprise, aimed
at small and medium businesses that have limited IT and security expertise. Insurers, customer
supplier questionnaires and NIST CSF 2.0 (which added a **Govern** function) all expect documented
policies, change control and measured controls. On the IT Support Officer side, the job ad explicitly
asks for reports, presentations, business updates, process improvement, following up on action items,
and communicating operational issues to management. P10 is where that half of the job is proven.

**Success = the measurable criteria** in the P10 plan §3: all 56 safeguards scored with evidence,
change management live with three worked changes, a ten-policy pack, a monthly report from 12+ KPIs,
a risk register and action tracker with ≥90% closed on time, and a recorded "State of IT" talk.

## 3. Design principles

1. **Evidence or nothing.** A safeguard is only scored `3` when a file proves it. The assessment tool
   (`scripts/cis_assessment.py`) refuses a `3` with no evidence source; an honest 70% beats an
   inflated 95%, and interviewers probe the number (plan §8).
2. **Governance owns nothing technical.** Every control P10 assesses is implemented by P1–P9. P10
   measures and reports; it does not re-architect. That keeps the separation honest and the evidence
   path short.
3. **Measure what is measurable now; label the rest.** Repository-derived KPIs (project readiness,
   evidence coverage, change and policy counts) are true measurements of this repository today.
   Lab-measured KPIs stay `not measured` until the lab runs — never estimated.
4. **Standard changes exist so the CAB is not bureaucracy.** Routine, repeatable, low-risk work is
   pre-approved in a catalogue; only normal and emergency changes reach a meeting.
5. **Business owners for business risks.** A risk owner who is always IT is a governance failure.
6. **Reports end in a decision request**, not a page of technical numbers (plan §8).

## 4. The CIS IG1 scope decision

**Chosen scope: CIS Controls v8.1, Implementation Group 1 — 56 safeguards.** Reasons:

- It is the correct fit for an 85-user company with one IT generalist and no security team. IG2 and
  IG3 assume dedicated security staff and are not the right lens for Halden.
- It is small enough to assess honestly in a project of this size and large enough to expose the real
  gaps (the awareness programme in Control 14 is the obvious one).
- It is a market-recognised baseline, so the score means something to an insurer or a customer's
  supplier questionnaire.

**Distribution of the 56 safeguards** (used to sanity-check the workbook and the chart):

| Control | Name | IG1 safeguards |
|---|---|---|
| 1 | Inventory and Control of Enterprise Assets | 2 |
| 2 | Inventory and Control of Software Assets | 3 |
| 3 | Data Protection | 6 |
| 4 | Secure Configuration of Enterprise Assets and Software | 7 |
| 5 | Account Management | 4 |
| 6 | Access Control Management | 5 |
| 7 | Continuous Vulnerability Management | 4 |
| 8 | Audit Log Management | 3 |
| 9 | Email and Web Browser Protections | 2 |
| 10 | Malware Defenses | 3 |
| 11 | Data Recovery | 4 |
| 12 | Network Infrastructure Management | 1 |
| 14 | Security Awareness and Skills Training | 8 |
| 15 | Service Provider Management | 1 |
| 17 | Incident Response Management | 3 |
| | **Total** | **56** |

**Deliberately excluded, with the reason:**

| Excluded | Why |
|---|---|
| Controls **13, 16 and 18** | They have **no IG1 safeguards**. Control 13 (network monitoring/defence) and 16 (application security) start at IG2; Control 18 (penetration testing) is IG3. Excluding them is the framework's decision, not a gap in the assessment. |
| **Controls 14.1–14.8 as scored items** | They are in the IG1 list but Halden has **no security awareness programme in the build kit**, so they cannot be scored `3`. They are recorded as the primary **90-day roadmap** gap and are scored honestly at `0`/`1` once the assessment runs. Excluding them from the scope altogether would inflate the score. |
| **NIST CSF 2.0 mapping** | The plan lists it as *optional* (P10 §5.1.6). A one-page CSF view can be added after the IG1 assessment is real; mapping an unscored assessment to a second framework adds no truth. |
| **CSAT automated scoring** | CIS CSAT requires an account and is interactive. The workbook is built by hand around the published payoff scale so the result is reproducible and reviewable in Git; CSAT remains a valid cross-check. |

**Scope is recorded as the `in_scope` column in** `data/cis-ig1-safeguards.csv`; all 56 rows are
currently `yes` (Control 14 included but expected to score low).

## 5. How evidence is traced from safeguard to artifact

The chain is deliberately one-directional and machine-checkable:

```
safeguard_id  →  configs/cis-ig1-evidence-map.csv  →  artifact_path  →  a file in projects/
      │                     │                                                     │
      │                     └── halden_expected_evidence (how, in words)          │
      │                     └── source_projects (P1…P9, or "roadmap")            │
      └── data/cis-ig1-safeguards.csv (score 0-3, written by hand)  ←── verified by reading ──┘
```

- `scripts/evidence_index.py` walks the map and reports, for each safeguard, whether the named
  artifact exists **today**. Because the lab has not run, most are `expected - not present` — that is
  the honest finding and it is why nothing is scored.
- `scripts/cis_assessment.py` refuses a score of `3` that has no evidence source, and refuses a `3`
  whose evidence source is a repository path that does not resolve to a real file. (The evidence
  *map* only says where evidence is expected; it is not itself proof.) So the score cannot drift away
  from the evidence.
- `scripts/monthly_report.py` refuses to render if a cited evidence file is missing. A management
  report therefore cannot link to a source that does not exist.

Where a safeguard comes from more than one project (for example 4.6, secure management, draws on the
P9 config-as-code work and the P1 GPO baseline), the map records both and the index counts it under
each.

## 6. Change-management process design

Three change types, because a single approval path is either too slow for routine work or too weak
for risky work (full definitions in `configs/change-type-matrix.csv`):

| Type | Approval | Example in Halden |
|---|---|---|
| **Standard** | Pre-approved in a catalogue once | Add a user via the P2 JML engine; monthly Ring1 patch approval |
| **Normal** | Weekly CAB (15 minutes) | New firewall rule (P6); LDAP channel binding enforcement (P3) |
| **Emergency** | ECAB by phone, retrospective within 2 business days | Block an actively exploited VPN vulnerability (a P5 P0 finding) |

Every normal or emergency RFC must carry: description, business reason, affected services (from the
P9 CMDB), a likelihood × impact risk score plus a short checklist, an implementation plan, a test
plan, a **rollback plan**, a communication plan, a maintenance window, a named approver and a
post-implementation review. The rule that gives the process teeth is simple and enforced in code: **a
change with no rollback plan cannot be approved** (`scripts/change_log.py` errors on it).

The register (`data/change-log.csv`) is validated on every run; the CAB agenda is generated from it
in the order the procedure specifies (emergencies first, then approvals, then implemented changes,
then reviews, then risks and actions). Decisions are **never written automatically** — the agenda's
decisions table stays `pending` until a human records a real decision.

Freeze periods (month-end for Finance, peak dispatch season for Operations) are agreed with the
departments and configured in `configs/change-policy-fields.yaml`.

The loop closes with P9: a **config drift alert** with no matching approved change record is an
unauthorised change, which raises a ticket, a root-cause note and a lesson added to the procedure.

## 7. The KPI set and why each is worth collecting

The full set (27 definitions, formula, source, target, RAG rule and owner) is in
`configs/kpi-definitions.csv`. Each row carries a `class`:

- **repository-derived** — computed by `scripts/collect_kpis.py` from files in this repo. Real today.
- **lab-measured** — needs the lab. Reported as `not measured` until the relevant phase runs.

The set is deliberately small enough to sustain monthly. The reasoning behind the main groups:

| Group | Why it earns its place |
|---|---|
| Identity (MFA coverage, leaver revocation, stale accounts) | Credential abuse is the most common initial-access vector; identity is the highest-leverage control and the easiest to measure from P2. |
| AD security (PingCastle score) | A single defensible number that tracks privileged-access hardening (P3). |
| Endpoint / patching / vulnerability | Where a small business is breached most often (unpatched, unsupported, unmanaged). P4/P5 produce these natively. |
| Backups (restore tests passed) | Attackers target backups; "periodically verify backups" is in the job ad for a reason. A backup that has not restored is not a backup. |
| Availability and service desk | The "are we supporting the business?" half of the report, from Uptime Kuma and GLPI (P9). |
| Change (success %, emergency %, unauthorised) | Governance health. A rising emergency share is the early warning that change control is failing. |
| Governance (CIS IG1 %, actions closed on time %, DoD items) | Whether the programme is actually moving, not just reporting. |

**Why not more KPIs:** a KPI nobody can act on is a distraction. Every definition has a named owner
and a target, and the monthly report ends with a decision request (plan §8: "reports full of technical
numbers without a 'so what' and a decision request").

## 8. Architecture of the governance cycle

![P10 governance architecture](diagrams/p10-architecture.svg)

`docs/diagrams/p10-architecture.svg` is both the design diagram and the portfolio hero image. It
shows the loop: business objectives → controls and policy → evidence from the nine projects →
CIS IG1 self-assessment → gap and risk register → change management → KPI dashboard and monthly
report → management review → improvement, with the P1–P9 data sources named on the evidence stage.

## 9. Deliverables and where they live

| Deliverable | File(s) |
|---|---|
| Assessment workbook + report | `data/cis-ig1-safeguards.csv`, `scripts/cis_assessment.py`, `reports/cis-ig1-assessment-*.md` |
| Evidence index | `configs/cis-ig1-evidence-map.csv`, `scripts/evidence_index.py` |
| Change process + register + agenda | `configs/change-type-matrix.csv`, `configs/change-policy-fields.yaml`, `data/change-log.csv`, `scripts/change_log.py` |
| Policy pack + register | `business/p10-policy-pack.md`, `data/policy-register.csv` |
| KPI pipeline + dashboard | `configs/kpi-definitions.csv`, `scripts/collect_kpis.py`, `scripts/governance_dashboard.py` |
| Monthly report | `scripts/monthly_report.py`, `business/p10-monthly-it-report.md`, `reports/monthly-it-report-*.md` |
| Risk register + action tracker | `data/risk-register.csv`, `data/action-tracker.csv`, `business/p10-risk-register.md` |
| Management suite | `business/p10-exec-summary.md`, `business/p10-cab-minutes.md`, `business/p10-state-of-it-talk.md` |
| Lab collection | `scripts/00-Collect-GovernanceEvidence.ps1`, `scripts/00-governance-preflight.sh`, `scripts/01-collect-kpi-evidence.sh` |

## 10. Risks in this design

| Risk | Mitigation |
|---|---|
| Scoring IG1 generously to look good | The tool refuses a `3` without evidence; the before/after chart is a labelled template until real scores exist |
| A CAB that is pure bureaucracy | Standard changes are pre-approved; the CAB is 15 minutes and has a fixed agenda |
| Policies nobody reads | Ten policies of 1–2 pages each, plain English, each with an owner, review date and version |
| Reports with numbers and no decision | Every report ends with a "decision requested" line; risks require a recommended decision |
| Risk owners all in IT | The register has a `business_owner` field and the methodology says IT cannot own a business risk |
| KPIs that need the lab being guessed | Lab KPIs are `not measured` by design, and the collector tests assert they are never numeric |
| Publishing a document that links to a missing file | `monthly_report.py` refuses to render on any missing evidence link |

## 11. Interview notes (design phase)

**"How do you know your controls are actually working?"** Not by believing the design — by requiring
evidence. Every safeguard scored 3 names a file that proves it, the assessment tool rejects a 3 with
no source, and the monthly report will not render if a cited evidence file is missing. Controls are
also re-assessed (quarterly) and drift-checked (P9), so a control that stops working shows up as a
changed config with no approved change record.

**"How do you get management to care about CIS controls?"** Translate them into their language: this
is what the insurer's questionnaire asks, this is the risk it reduces, this is the cost and this is
what happens if we defer. Then give them one page with a RAG status and a decision request — not 56
rows of safeguards. The framework is the *how*; the board cares about the *risk* and the *cost*.

**"What is the difference between a KPI and a KRI?"** A KPI measures how well a process is
performing against a target (SLA compliance 92% against a 90% target). A KRI measures exposure that
predicts trouble — open KEV vulnerabilities, the emergency-change share, stale privileged accounts.
KPIs tell you whether you are doing the work well; KRIs tell you whether you are about to have a bad
month. P10 reports both, and the risk register is where the KRIs get owners.

---

*Next step: Phase 1 — run the CIS IG1 assessment (in Mode A the owner runs `scripts/cis_assessment.py`
and pastes the output back; nothing is scored until an artifact for that safeguard has been seen).*
