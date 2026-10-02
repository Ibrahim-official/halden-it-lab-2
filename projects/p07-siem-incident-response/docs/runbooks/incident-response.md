# Runbook — Incident response (full lifecycle)

**Applies to:** all incidents · **Owner:** Incident Lead · **Companion:** `business/p07-ir-plan.md`
**Alignment:** NIST SP 800-61r3 / NIST CSF 2.0 (Govern · Identify · Protect · Detect · Respond ·
Recover). This runbook is the technical companion to the business-facing plan.

Use this runbook for any SEV1/SEV2 incident. For a specific detection, use the matching playbook
first (suspicious-logon, ransomware-pre-encryption, privileged-group-change) and return here for the
lifecycle around it.

---

## Phase 1 — Detect and validate (minutes 0-30)

| Step | Action | Output |
|---|---|---|
| 1.1 | Receive the alert; identify the rule id and severity | Alert noted in the timeline |
| 1.2 | Validate it is real (not a mis-tuned rule) | Confirmed / false positive with a reason |
| 1.3 | Assign a severity (SEV1/2/3) using `configs/alert-severity-triage.csv` | Declared severity |
| 1.4 | Declare the incident and appoint an **Incident Lead** | Incident record opened (`INC-YYYY-NNN`) |
| 1.5 | Start the timeline in UTC (`data/incident-timeline-template.md`) | Timeline begun |

**Do not skip 1.1-1.5 to "just fix it".** Undeclared incidents are the ones that go wrong: no
timeline, no evidence, no lessons.

---

## Phase 2 — Contain (minutes 30-120, faster for ransomware)

Goal: stop the spread and stop the damage, **without destroying evidence**.

| Order | Action | Notes |
|---|---|---|
| 2.1 | Isolate affected hosts (network isolation, not power-off) | Power-off loses memory evidence |
| 2.2 | Disable (not delete) affected accounts | Deletion loses evidence and is hard to reverse |
| 2.3 | Protect the backups (BKP01, P8) — confirm the attacker cannot reach them | Attackers target backups first |
| 2.4 | Block command-and-control at FW01/FW02 with a timeout | Never a permanent rule without review |
| 2.5 | Confirm containment: no new alerts for the same actor | Containment verified, not assumed |

**Roles** (from the IR plan): Incident Lead (decides, coordinates), Technical (works the evidence),
Communications (staff/customer messages), Management decision-maker (payment, disclosure, downtime).

---

## Phase 3 — Investigate and scope

- Build the timeline from **Wazuh events**, not memory.
- Find the entry point: phishing? exposed service? credential abuse? (Check P3/P5/P6 findings too.)
- Scope: every account and host the actor touched. Correlate D1/D4/D5/D6/D7/D9/D10/D11 over the
  window.
- Decide the "assume compromised" boundary: if directory replication was used (D11), assume all
  credentials are in scope.

---

## Phase 4 — Eradicate

- Remove persistence: rogue group memberships, accounts, services, tasks, keys.
- Close the entry point **before** restoring anything, or you re-infect.
- Reset credentials for everything in scope; re-enrol MFA where it exists (P2).
- Rebuild compromised hosts from known-good images where the root cause is not certain.

---

## Phase 5 — Recover

- Restore data from a **verified** backup (P8), not from a snapshot that may predate the compromise.
- Bring services back in a controlled order and watch the SIEM for the detections returning.
- Confirm the business is actually working, not just the servers: can users log in, open files, use
  the service desk.

---

## Phase 6 — Post-incident

| Step | Action |
|---|---|
| 6.1 | Write the incident report: what happened, timeline, root cause, impact, what worked |
| 6.2 | Mark detection quality honestly: did the rule fire? how fast? could it have been earlier? |
| 6.3 | Hold a post-incident review within a week; no blame, only actions |
| 6.4 | Record improvement actions with owners and dates; track them in P10 |
| 6.5 | Update runbooks, detection tuning (`docs/tuning-log.md`) and the monitoring policy as needed |

---

## Communication (what to say, and when)

| Audience | When | Message shape |
|---|---|---|
| IT / on-call | Immediately | Technical: what fired, what is affected, what to do |
| Management (MD) | SEV1 within 15 min | Impact and decision needed; no technical depth |
| Affected department heads | SEV2 within 1 h | What is affected, what users should do |
| All staff | When the service impact is visible | Plain language, what to do, when the next update comes |
| Regulator / insurer / police | Per the IR plan, on advice | Only on legal advice; deadlines are in the plan |

Never speculate publicly. State facts, state the next update time, and keep to it.

---

## Evidence handling

- Preserve before cleanup; sanitize before publishing; raw Wazuh archives never leave the lab raw
  (AGENTS.md 4.6).
- Keep the chain of custody table in the incident record (who collected what, when, hash).
- Keep one authoritative timeline; everyone writes to the same one.

## Rollback and safety

- Every containment step is reversible: isolation ↔ reconnect; disable ↔ enable; temporary block ↔
  remove (or expiry).
- The irreversible steps — deleting an account, wiping a host, paying — require the Incident Lead and,
  for payment or disclosure, the management decision-maker.

> **Honest framing:** this runbook is the defensive lifecycle — what to do when something is detected.
> Any attack technique referenced was simulated only in an authorised, snapshotted lab exercise
> (`scripts/07`, approval required per AGENTS.md R6 and R1).
