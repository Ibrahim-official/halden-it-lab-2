# P3 — Phase 0: Design document (design before you build)

**Project:** P3 AD Security Assessment and Privileged Access Hardening
**Company:** Halden Distribution Ltd. (fictional, 85 users) · **Domain:** `ad.halden.internal`
**Status:** Phase 0 complete · **Owner:** Muhammad Ibrahim Akmal · **Mode:** A (Advisor)
**Spec:** [`docs/plan/P03-ad-security-assessment-privileged-access.md`](../../../docs/plan/P03-ad-security-assessment-privileged-access.md)

> Why design first: a security assessment is only useful if you decide, *before* you run anything,
> what you are measuring, how you will score what you find, how you will prove a fix worked, and
> where the boundary of the exercise lies. That last point matters most here: P3 uses attack-path
> tooling, so the authorisation and the lab-only guard are part of the design, not an afterthought.

---

## 1. Goal and scope

Reduce the chance that one compromised workstation becomes a compromised domain, and be able to
show the evidence for it:

- Baseline the directory with PingCastle, Purple Knight and BloodHound CE (all free tooling).
- Produce a risk-rated findings register with owners, target dates and evidence.
- Remediate: AD Recycle Bin, Domain Admin reduction, pre-authentication and delegation cleanup,
  Print Spooler off on DCs, password policy (FGPP), Windows LAPS, a three-tier privileged access
  model with logon restrictions, gMSAs, Kerberos and legacy-protocol hardening.
- Re-assess and publish a before/after comparison, with residual risk formally accepted where it
  is accepted.
- Produce the business layer: a 1-page executive summary, the findings register, an admin access
  standard and a five-slide management deck.

Out of scope for P3: endpoint hardening and BitLocker (P4), vulnerability scanning (P5), network
segmentation of the PAW and the management VLAN (P6), SIEM detection content and incident
playbooks (P7), backup of domain controllers (P8), formal governance and the KPI report (P10).
P3 is where the Tier 0 reality of those projects is first written down.

## 2. Business context (why this exists)

Halden has one shared local administrator password on every workstation, four people in Domain
Admins including one who has left, service accounts whose passwords have not changed in years, and
a password policy that allows seven characters with no lockout. Phishing one member of staff is
therefore enough to reach the domain in hours rather than weeks.

**Market context (from `docs/plan/00-research-and-selection.md`, Verizon 2025 DBIR):** credential
abuse is the most common initial access vector at 22% of breaches, and ransomware appears in 88% of
SMB breaches. Ransomware operators escalate to Active Directory privilege first, because domain
administrator rights let them push encryption to every machine at once. That is the business case
for this project.

**Success = the measurable criteria** in the P3 plan: PingCastle global risk score reduced by at
least 70% with each of its four categories recorded, Purple Knight critical indicators resolved or
formally risk-accepted, no attack paths from ordinary users to Domain Admins, 100% of workstations
and member servers on unique rotating LAPS passwords, no daily-use accounts in Domain Admins, Tier 0
accounts unable to log on to lower-tier machines, service accounts converted to gMSA, and every
finding carrying an owner and evidence.

## 3. Design principles

1. **Authorised, and only in the lab.** Attack-path tooling runs only against `ad.halden.internal`,
   only after the owner's written authorisation is recorded in the change record. Every script has
   a lab guard and the assessment scripts refuse to run without an authorisation reference.
2. **Measure before you claim.** Every metric has a before value and an after value, each with a
   source file in `evidence/public/`. Nothing is published until it has been measured.
3. **Seeded weaknesses, honestly labelled.** The lab is deliberately made weak in Phase 0 so the
   assessment has something real to find, and every published page says so.
4. **Audit, analyse, enforce.** Breaking changes (NTLM, Kerberos encryption, LDAP signing) go
   through an audit phase first, with the events reviewed before the control is enforced.
5. **Verify, do not assume.** "Applied" and "enforced" are different. Each control has a
   verification step (`11-Verify-Remediation.ps1`) and the deny-logon rules are tested by a human.
6. **Least privilege by structure, not by discipline.** Separate admin accounts, tiered groups and
   delegated rights, so nobody needs Domain Admin to do their job.
7. **Raw output stays raw.** BloodHound databases, PingCastle HTML and Purple Knight exports name
   internal accounts and describe exactly how the domain could be attacked. They stay in
   `evidence/raw/` (git-ignored) and only sanitized summaries are published.

## 4. What will be assessed (and what each tool answers)

| Tool | Question it answers | Output |
|---|---|---|
| **PingCastle** (basic edition, free) | What is the overall hygiene of this directory, and how does it break down into stale objects, privileged accounts, trusts and anomalies? | HTML/XML healthcheck, global score, category scores |
| **Purple Knight** (free) | Which specific well-known AD indicators are present right now, and which are critical? | Indicator report per category |
| **BloodHound CE + SharpHound** (free, open source) | Which existing rights and group memberships create a *path* from an ordinary account to a highly privileged one? | Graph query results and path counts |
| **Windows LAPS** (built into Server 2019+/Windows 11) | Does every endpoint have its own rotating local administrator password, and who can read it? | LAPS policy, Event 10018, `Get-LapsADPassword` results |
| **Microsoft `New-KrbtgtKeys.ps1`** | Is the krbtgt password old, and what would a safe rotation look like? | Simulation output (the reset itself is a separate scheduled change) |

## 5. How risk is scored

Findings are normalised into one register. Scoring is deliberately simple so a non-technical reader
can follow it and so the same rule can be applied by anyone reviewing the register:

- **Likelihood (1–5)** — how readily this could be used by someone with network access.
- **Impact (1–5)** — how far the damage spreads if it is used. Impact 5 is domain-wide.
- **Risk score** — Likelihood × Impact (1–25).
- **Priority** — P0 (≥20, contain within 3 days), P1 (≥12, fix this iteration, 14 days),
  P2 (≥6, planned work, 30 days), P3 (backlog or risk-accept, 90 days).
- **Escalation** — a finding in the *privileged-access*, *delegation* or *credential-exposure*
  categories with a score of 12 or more moves up one band, capped at P0. Handing an attacker direct
  control of the domain is treated as urgent even when the raw numbers are borderline.

The rules live in `configs/p03-remediation-priority-rules.json`; the schema is
`configs/p03-findings-register-schema.csv`; the scoring code is
`scripts/04-New-FindingsRegister.py` and is covered by unit tests in `scripts/tests/`.

## 6. The tiering model

| Tier | Scope | Admin accounts | Can log on to | Why this boundary |
|---|---|---|---|---|
| **Tier 0** | DCs, AD itself, Entra Connect (P2), PKI, DC backups | `adm-t0-*` | DCs and the PAW only | A Tier 0 compromise is a domain compromise, so Tier 0 credentials must never be exposed to a workstation |
| **Tier 1** | Member servers and the applications on them | `adm-t1-*` | Member servers only | Server administration should not need, or grant, rights over workstations |
| **Tier 2** | Workstations, users, helpdesk work | `adm-t2-*` | Workstations only | The helpdesk's real job is password resets and unlocks, which delegation grants without Domain Admin |

The model is applied in the `_Admin` OU tree (`Tier0|Tier1|Tier2\Accounts|Groups`, plus `PAW\Devices`).
Every IT person keeps a separate daily-use account with no administrative rights. Admin accounts are
marked *sensitive and cannot be delegated*; human Tier 0 accounts join **Protected Users** — after a
test account has proven that Kerberos still works for them. Service accounts and computer accounts
never go into Protected Users. The full model is in `configs/p03-tiering-model.csv` and the policy is
`business/p03-privileged-access-policy.md`.

## 7. Remediation phases and the control that proves each one

| Phase | Change | Control that proves it |
|---|---|---|
| 2 | AD Recycle Bin, Domain Admin reduction, pre-auth and delegation cleanup, Spooler off, FGPP | `11-Verify-Remediation.ps1` PASS rows; NTLM/4769 events |
| 3 | Windows LAPS with encrypted AD backup and delegated read | Event 10018; `Get-LapsADPassword` succeeds for helpdesk, is denied for a standard user |
| 4 | Tiering, separate admin accounts, deny-logon GPOs, Protected Users, PAW, helpdesk delegation | Denied RDP test with a Tier 0 account; helpdesk can reset a Sales user but not a Tier 0 admin |
| 5 | gMSA, AES-only Kerberos after audit, krbtgt rotation planned | `Test-ADServiceAccount` = True; RC4 request events reviewed before enforcement |
| 6 | LM level 5, SMB signing, SMBv1 removed, LDAP signing and channel binding, LLMNR off | Audit events reviewed first, then configuration verified per host |
| 7 | Re-assessment and report | PingCastle and BloodHound re-run; before/after table; risk-acceptance entries |

## 8. Lab host and VM plan

P3 runs on the P1 environment and adds one VM.

| VM | Role in P3 | Notes |
|---|---|---|
| DC01 / DC02 | Target of the assessment and of every hardening step | 192.168.10.10/.11, Server 2025 |
| FS01 | Member server; source of the unconstrained-delegation finding | 192.168.10.20 |
| LNX01 | Hosts the BloodHound CE containers | 192.168.10.30, Ubuntu 24.04 |
| WS01 | Workstation test client for LAPS and deny-logon | DHCP |
| **WS02** | **Added in P3** as the Tier 0 Privileged Access Workstation and as the "denied" test client | Windows 11 Enterprise eval, DHCP |
| FW01 | Gateway; the PAW's network isolation is a P6 change | 192.168.10.1 |

RAM concern: the P1 host has 16 GB. BloodHound CE runs its own database containers, so it is started
only while the assessment is running and stopped afterwards (`03-Deploy-BloodHoundCE.sh --teardown`).

## 9. Evidence plan

Per AGENTS.md 4.5, every phase defines its evidence before it runs. Names follow
`pXX-phN-<what>-<before|after|result>.<ext>`.

| Phase | Evidence to capture | Published form |
|---|---|---|
| 0 | Seed log | Not published: it describes exactly what was made weak |
| 1 | PingCastle before (HTML + score), Purple Knight indicators, BloodHound path graph, findings register | Sanitized score screenshots, a sanitized summary graph, the register as PDF |
| 2 | Quick-win log, NTLM audit events | Sanitized CSV extract of the log |
| 3 | LAPS schema and policy, Event 10018, access allowed/denied | Screenshots with any password value **blurred** |
| 4 | Tiering log, denied RDP screenshot, Protected Users membership, helpdesk delegation test | Screenshots |
| 5 | `Test-ADServiceAccount` = True, Kerberos audit events, krbtgt simulation output | Screenshot and a sanitized log excerpt |
| 6 | Posture before/after CSV, SMBv1 state | Sanitized CSV |
| 7 | PingCastle after, BloodHound after, verification CSV, before/after table | Sanitized screenshots and a CSV table |

**Screenshots must not contain a LAPS password, a recovery key, a password hash, an MFA secret or a
real email address.** Blur them before anything moves to `evidence/public/` (AGENTS.md 4.6).

## 10. Honest scope and limitations of a home-lab assessment

This is a real assessment of a real directory, but it is not a penetration test and it is not a
production engagement. Saying so is part of the work:

- **The weaknesses were seeded on purpose.** Anyone reading the score must know that the "before"
  state was constructed in Phase 0 to be realistic, not inherited from a real company.
- **One forest, one domain, no trusts.** PingCastle's *trust* category has almost nothing to find
  here; a real inherited environment usually has trust relationships and legacy domains.
- **No cloud hybrid at assessment time.** Entra Connect and cloud identity arrive with P2; the
  hybrid-specific exposures are therefore described but not measured in P3.
- **Small scale changes what "100%" means.** "100% of endpoints have unique LAPS passwords" is true
  of a handful of VMs, not of 85 real laptops with a mix of hardware and BIOS configurations.
- **No attack exploit is actually executed.** The tooling maps *potential* paths and reports
  configuration; no credential is cracked and no exploit chain is run. The plan's "attack-path"
  language is about reachability graph paths, not about a demonstrated compromise.
- **Time-boxed.** A real engagement would include application-level review, log review over a
  meaningful period, and interviews with the people who actually run the environment.

## 11. Snapshot and rollback plan

- **Before every phase:** snapshot DC01 and DC02 (`snap-p3-ph<N>-before`), plus FS01 and WS01 for
  Phase 6, and WS02 once it exists.
- **Phase 3 is the risky one:** `Update-LapsADSchema` changes the forest schema and is not
  reversible by removing an attribute. Snapshot both DCs together before it.
- **Phase 5:** the krbtgt reset is deliberately excluded from automation. It is a separate change
  with a strict wait between the two resets; see `docs/runbooks/run-the-assessment.md`.
- **Rollback per phase:** revert the snapshots and re-run the previous phase's scripts (they are
  idempotent). GPO changes revert by setting the settings back to "Not Configured". Reverting a
  domain controller snapshot can disturb replication, so forward fixes are preferred on DCs and a
  DC revert is recorded in `DECISIONS.md`.

## 12. Risks

| Risk | Mitigation |
|---|---|
| Assessment tooling pointed at the wrong network | Hard-coded lab guard in every script; the assessment scripts also require an authorisation reference |
| A published screenshot leaks a LAPS password or a path graph usable against a real domain | Sanitization checklist applied before anything moves to `evidence/public/`; raw exports never published |
| A hardening change breaks something (NTLM, Kerberos, LDAP) | Audit → analyse → enforce, with the audit events reviewed before enforcement |
| Deny-logon rules lock out the only working admin account | Break-glass built-in Administrator excluded from the deny rules and its password stored offline |
| Protected Users breaks a service or computer account | Only human Tier 0 accounts are added, and only after a test account proves Kerberos still works |
| BloodHound containers exhaust the 16 GB host | Start on demand, tear down after; it is not left running |
| Evaluation licences expiring mid-project | Tracked in `PROGRESS.md` (Server 180 days, Windows 11 90 days) |

## 13. Decisions and open items

Design decisions taken here (to be recorded in `DECISIONS.md` by the parent session):

1. Use PingCastle basic, Purple Knight and BloodHound CE — all free — rather than a paid platform.
2. Score findings with Likelihood × Impact (1–25) and four priority bands, so the register is
   readable by non-specialists.
3. Report **BloodHound CE path counts only**, and publish no exploit procedure: what matters to the
   business is reachability, and the remediation is the point of the page.
4. krbtgt rotation stays as a documented, separately scheduled change rather than part of the
   automated build.

Open items for the owner: confirm the exact authorisation reference for the change record, confirm
the Tier 0 admin account names after Phase 4 runs, and decide whether the PAW is WS02 or a separate
VM.

## 14. Interview notes (phase 0)

**"How would you explain a PingCastle score to a non-technical director?"** As a hygiene score, not
a penetration test result: "this tells us how many of the well-known weak settings an attacker
counts on are present in our directory, and it groups them into staleness, privileged accounts,
trusts and anomalies. It is a to-do list with numbers, not a verdict on our security." Then the
business consequence: a lower score means fewer shortcuts available to an attacker who already has
one account.

**"Why does tiering matter?"** Because credential exposure is the actual risk. If a domain
administrator reads email on their workstation, then compromising that workstation compromises the
domain. Tiering removes the reason for privileged credentials to be typed into a low-trust machine
at all, and the deny-logon rules enforce it rather than relying on habit.

**"Why keep the raw tool output unpublished?"** Because a HealthCheck report or a BloodHound
database is a map of how to attack the domain: it names the accounts to target and the paths to
follow. It belongs in the protected evidence folder, and what gets published is a sanitized
summary — the score, the categories, and the fact that remediation changed them.

---

*Next step: Phase 0 execution — run `00-Test-AssessmentGate.ps1` with the owner's authorisation
reference, snapshot DC01/DC02, then `01-Seed-Weaknesses.ps1` (Mode A: the owner runs the commands
and pastes the output back).*
