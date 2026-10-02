# P10: IT Governance Capstone (CIS IG1 Scorecard, Change Control, Policy Pack and Management Reporting)

> **Pitch:** Turned nine technical projects into a governed IT function. Assessed the company against **CIS Controls v8.1 Implementation Group 1** (56 safeguards) before and after, going from **X% to Y%** implemented. Introduced ITIL-style change management with a CAB, wrote a 10-policy IT policy pack, and delivered an automated monthly IT operations KPI report plus a board-style "State of IT" presentation with a costed 90-day roadmap.

**Anchor score:** 97 (merged with #45 change mgmt, #46 KPI report, #47 policy pack, #48 process mapping, #50 cost optimization) · **Time:** about 1.5 weeks · **Depends on:** P1–P9 (it measures and reports on them)

---

## 1. Business problem

Halden's management can't answer basic questions: *Are we secure? Are we getting better? What does IT need money for? What changed last week, and who approved it?* IT work happens but isn't visible. Changes are made on a Friday afternoon without telling anyone. There are no written policies, which the cyber-insurance renewal questionnaire now asks for.

**Market evidence:** CIS describes **IG1 (56 safeguards)** as essential cyber hygiene and an emerging minimum standard for all enterprises, aimed at SMBs with limited IT/security expertise. Insurers, customers' supplier questionnaires and frameworks such as NIST CSF 2.0 (which added a **Govern** function) all expect documented policies, change control and measured controls. On the IT Support Officer side, the ad explicitly asks for reports, presentations, business updates, process improvement, following up on action items, and communicating operational issues to management.

## 2. JD coverage

| Ad | Bullet proven |
|---|---|
| Officer | **Prepare reports, presentations, documentation, and business updates** |
| Officer | **Assist in process improvement and assigned business projects** |
| Officer | **Coordinate with teams and follow up on assigned tasks and action items** |
| Officer | Understand company **operations, policies, processes, and business objectives** |
| Officer | **Identify operational issues and communicate them to the relevant management** |
| Officer | Maintain accurate records and ensure timely completion |
| SysAdmin | **Follow IT security policies, change-control procedures, and access-management standards** |
| SysAdmin | **Perform regular security checks** (IG1 assessment) |

## 3. Success criteria

- [ ] **CIS IG1 assessment:** all 56 safeguards scored *before* (inherited state) and *after* (post P1–P9), each with evidence linked to project artifacts
- [ ] **Change management** live in GLPI: standard/normal/emergency types, RFC template, risk assessment, CAB approval, change calendar, post-implementation review. **All P1–P9 changes logged** (retroactively for the earlier ones), plus 3 new changes run end-to-end
- [ ] **Policy pack:** 10 short policies/standards approved by "management", with a staff acknowledgement process
- [ ] **Monthly IT KPI report**, generated automatically from P2–P9 data, with 12+ KPIs, trends and RAG status
- [ ] **Risk register** and **consolidated action tracker** (all actions from P2 reviews, P3 findings, P7 tabletop, P8 drill), with owners and due dates and **≥90% closed on time**
- [ ] **"State of IT" presentation** (10–12 slides) with a 90-day roadmap and budget asks, delivered as a recorded 10-minute talk

## 4. Tools and cost

[CIS Controls v8.1](https://www.cisecurity.org/controls) + the IG1 safeguard list (free download) or the free [CIS CSAT](https://www.cisecurity.org/controls/cis-controls-self-assessment-tool-cis-csat) · GLPI Changes module (P9) · Power BI Desktop (free) or Excel · PowerShell/Python for data collection · PowerPoint/Google Slides · OBS Studio for the recorded talk. **Cost: free.**

## 5. Step-by-step action plan

### Phase 0: Understand the business objectives (Day 1)
1. Write a 1-page **"Halden IT context"**: business objectives for the year (e.g. grow online orders 20%, open a second warehouse, pass a major customer's supplier security questionnaire, renew cyber insurance without a premium hike), and how IT supports each.
2. Map IT KPIs to those objectives. The report should answer "are we supporting the business?", not just "are servers up?". **This is what separates an IT Support Officer from a technician.**

### Phase 1: CIS IG1 gap assessment, before and after (Day 2–3)
1. Build `business/p10-cis-ig1-assessment.xlsx`, one row per IG1 safeguard (56 rows):
   `Control · Safeguard ID · Title · Asset type · Security function · BEFORE status · AFTER status · Evidence (link to P# artifact) · Gap · Action · Owner · Target date`
   Status scale: **0 Not implemented · 1 Partially · 2 Implemented on some systems · 3 Fully implemented and evidenced**.
2. **Before:** score the *inherited* Halden (Section 1 of each project's problem statement). This is an honest reconstruction of the starting state.
3. **After:** score today, **only counting what has evidence**. Examples of the mapping:

   | CIS Control | IG1 examples | Evidence from |
   |---|---|---|
   | 1 Asset inventory | 1.1 inventory, 1.2 address unauthorized assets | P9 GLPI + reconciliation |
   | 2 Software inventory | 2.1, 2.2 supported software, 2.3 unauthorized software | P9, P4 (Win10 EoL) |
   | 3 Data protection | 3.1 data mgmt process, 3.3 ACLs, 3.6 encrypt end-user devices | P1 AGDLP, P4 BitLocker |
   | 4 Secure configuration | 4.1 config process, 4.4/4.5 firewalls, 4.7 default accounts | P4, P6, P3 LAPS |
   | 5 Account management | 5.1 inventory, 5.3 disable dormant, 5.4 restrict admin privileges | P2, P3 |
   | 6 Access control | 6.1/6.2 grant/revoke process, 6.3–6.5 MFA | P2, P6 VPN MFA |
   | 7 Vulnerability mgmt | 7.1 process, 7.3/7.4 automated OS/app patching | P5 |
   | 8 Audit log mgmt | 8.1 process, 8.2 collect, 8.3 storage | P7 |
   | 9 Email/browser | 9.1 supported browsers, 9.2 DNS filtering | P4, P6 |
   | 10 Malware defenses | 10.1–10.3 anti-malware, autorun | P4 |
   | 11 Data recovery | 11.1–11.4 recovery process, automated, protected, isolated copy | P8 |
   | 12 Network infrastructure | 12.1 up-to-date network infrastructure | P5 firmware, P6 |
   | 14 Security awareness | 14.1–14.8 training | *Gap → roadmap* (e.g. phishing training) |
   | 15 Service providers | 15.1 inventory of providers | P9 vendor register |
   | 17 Incident response | 17.1–17.3 roles, contacts, reporting process | P7 |

   (Controls 13, 16 and 18 have no IG1 safeguards.) Always check against the official v8.1 safeguard list. The table above is a guide, not a substitute.
4. Calculate the **% implemented** overall and per control. Build a before/after bar chart per control. **Headline metric for the resume.**
5. Remaining gaps (Control 14 training is a likely one) go into the **90-day roadmap**.
6. Optional: map the same evidence to the **NIST CSF 2.0** functions (Govern, Identify, Protect, Detect, Respond, Recover) for a one-page executive view.

### Phase 2: Change management (Day 4–5)
1. `business/p10-change-management-procedure.md` (2–3 pages):

   | Type | Definition | Approval | Example |
   |---|---|---|---|
   | **Standard** | Pre-approved, low-risk, repeatable, documented procedure | None per instance (catalogue approved once by CAB) | Add user to a role group via JML, monthly Ring0 patching |
   | **Normal** | Everything else | CAB (weekly, 15 minutes: IT Lead + affected dept head + management for High risk) | New firewall rule, GPO change, server upgrade |
   | **Emergency** | Needed now to restore service or stop an active threat | ECAB (IT Lead + 1 manager, by phone), **retrospective review within 2 business days** | Blocking an actively exploited VPN vuln (P5 P0) |

2. **RFC template** (GLPI Change form): description, reason/business benefit, affected services/users (from the CMDB), **risk assessment** (likelihood × impact + a short checklist: touches Tier 0? affects many users? tested? rollback tested?), implementation plan, **test plan**, **rollback plan**, communication plan, schedule/maintenance window, approver(s), post-implementation review.
3. **Change calendar** with freeze periods (month-end for Finance, peak dispatch season for Ops). Agree these with the departments.
4. **Retroactively log P1–P9 changes** (about 15–20 RFCs). Then run **3 new changes end-to-end** with a simulated CAB and minutes:
   - Normal: "Enforce LDAP channel binding" (from P3 audit data)
   - Standard: "Monthly Ring1 patch approval" (P5)
   - Emergency: "Block exploited edge vulnerability" with a retrospective review
5. **Close the loop with P9 drift detection:** an unapproved change is detected, a ticket is raised, the root cause is recorded, and the lesson learned is added to the procedure or training. Show one example.
6. Change KPIs: number of changes by type, **% successful**, % emergency (a high share is a warning sign), changes causing incidents, unauthorized changes detected.

### Phase 3: IT policy pack (Day 6–7)
Ten **short** (1–2 pages each), plain-English documents in BookStack (P9) and PDF, each with: purpose, scope, policy statements, roles, exceptions process, review date, owner, version.

| # | Policy / standard | Draws on |
|---|---|---|
| 1 | Information Security Policy (umbrella, signed by the MD) | All |
| 2 | Acceptable Use Policy (staff-facing; includes AI tool use, a current shadow-IT issue) | P4, P9 |
| 3 | Access Control & Identity Standard (JML, least privilege, MFA, reviews) | P2 |
| 4 | Privileged Access Standard (tiering, LAPS, break-glass) | P3 |
| 5 | Endpoint Security Standard | P4 |
| 6 | Patch & Vulnerability Management Policy | P5 |
| 7 | Network & Remote Access Standard | P6 |
| 8 | Logging, Monitoring & Incident Response Policy | P7 |
| 9 | Backup & Recovery Policy | P8 |
| 10 | Change Management & Asset Management Policy | P9, P10 |

- **Acknowledgement process:** staff read and acknowledge the AUP (GLPI form or a Microsoft Form), tracked as % acknowledged. New starters get it in the JML welcome pack (P2).
- **Exceptions register** (consolidate P4 and P5 exceptions): one place, with owner and expiry.

### Phase 4: KPI data pipeline and monthly report (Day 8–9)
1. `scripts/Collect-ITKpis.ps1` gathers the data each month into `kpi/YYYY-MM.csv`:

   | Area | KPI | Source | Target |
   |---|---|---|---|
   | Identity | MFA coverage % | Entra / P2 report | 100% |
   | Identity | Leavers revoked within SLA % | P2 audit log | 100% |
   | Identity | Stale enabled accounts | P2 hygiene report | 0 |
   | AD security | PingCastle score | P3 monthly run | ≤ 20 |
   | Endpoint | Endpoint compliance % | P4 report | ≥ 95% |
   | Endpoint | Unsupported OS devices | P4/P9 | 0 by Q-end |
   | Patching | Patch compliance ≤14 days % | P5 / WSUS | ≥ 95% |
   | Vulns | Open KEV vulns / overdue by tier / MTTR | P5 dashboard | 0 / 0 / trend ↓ |
   | Monitoring | High alerts, incidents by severity, MTTD/MTTR | P7 | trend |
   | Availability | Uptime % critical services | Uptime Kuma | ≥ 99.5% |
   | Backup | Restore tests passed | P8 | 100% |
   | Service desk | Tickets, SLA compliance %, FCR %, backlog age | P9 GLPI API | ≥ 90% SLA |
   | Change | Changes, success %, emergency %, unauthorized | P10/P9 | success ≥ 95% |
   | Governance | CIS IG1 % implemented, actions closed on time % | P10 tracker | ↑ / ≥ 90% |

2. **Power BI (or Excel) dashboard** with RAG status, 3-month trends, and a "top 3 risks" panel from the risk register.
3. **Monthly IT report template** (`business/p10-monthly-it-report.md` → PDF, **2 pages max**):
   1. Summary in 3 sentences (what went well, what didn't, what we need)
   2. KPI table (RAG) with trends
   3. Notable events (incidents, major changes, outages) and business impact
   4. Risks and issues needing management attention (**with a recommended decision**)
   5. Actions: completed, overdue (owner/why), upcoming
   6. Next month's plan
   Produce **3 consecutive monthly reports** from lab data so they show trend and follow-through.
4. **Risk register** (`business/p10-risk-register.xlsx`): ID, risk statement ("If… then… resulting in…"), likelihood, impact, score, owner (**a business owner, not IT**), existing controls, treatment (mitigate/accept/transfer/avoid), actions, residual score, review date. Seed it from P3/P4/P5/P8 findings.
5. **Consolidated action tracker:** every action from every project in one list, reviewed weekly. Track % closed on time.

### Phase 5: "State of IT" presentation and 90-day roadmap (Day 10–11)
10–12 slides, one message per slide, written for non-technical management:
1. Where we started (the inherited state, in business terms)
2. What we did in 90 days (P1–P9 in one visual timeline)
3. **CIS IG1: X% → Y%** (before/after chart)
4. Identity: MFA 0% → 100%, leaver revocation days → minutes
5. Resilience: "We can recover the business in X hours, tested on [date]"
6. Security: attack paths to DA N → 0, KEV exposure, detection coverage
7. Service: SLA %, top recurring issues fixed
8. **Top 5 remaining risks** (from the register)
9. **90-day roadmap** (security awareness training + phishing simulation, Win10 replacement, real offsite backup subscription, Intune/Autopilot evaluation, second firewall for HA)
10. **Budget asks** with cost, risk reduced and option to defer (costed: e.g. device replacements from P4, offsite storage from P8, a training platform)
11. Decisions needed today
12. Appendix: KPI definitions

Record a **10-minute talk** (OBS) and put it in the portfolio. Interviewers rarely see an IT candidate present to management, and the ad asks for exactly that.

### Phase 6: Package the whole portfolio (Day 12)
1. **Portfolio landing README** (GitHub profile or `halden-it-portfolio` repo): the Halden story in 5 lines, a table of P1–P10 (problem → what I built → result metric → link), architecture diagram, 3-minute demo video link.
2. **A 1-page "results" sheet** (PDF) to attach to applications.
3. **LinkedIn:** one post per project over 10 weeks (short: problem, what you built, one metric, one lesson, link).
4. **Resume "Projects" section** (see below), plus a line in the summary: *"Built and documented a full SMB IT environment (85-user simulation): AD, identity lifecycle, hardening, patch/vuln mgmt, SIEM, backup/DR, ITSM and governance, measured against CIS IG1 (X% → Y%)."*

## 6. Business layer

This entire project is the business layer. Main artifacts: IG1 assessment, change procedure + CAB minutes, policy pack, 3 monthly reports, risk register, action tracker, State of IT deck + recording.

## 7. Evidence to capture

IG1 before/after chart · change calendar + a completed RFC with CAB approval + PIR · unauthorized-change example · policy pack index + acknowledgement % · Power BI dashboard · 3 monthly reports · risk register heat map · action tracker (closed on time %) · presentation recording.

## 8. Common pitfalls

- Scoring IG1 generously. **Only count evidenced safeguards.** An honest 70% beats an inflated 95%, and interviewers will probe it.
- Long policies nobody reads. Keep them to 1–2 pages, in plain English, with an owner and review date.
- A CAB that's pure bureaucracy. Standard changes exist so routine work doesn't need a meeting.
- Reports full of technical numbers without a "so what" and a decision request.
- Risk owners who are all IT. Business risks belong to business owners.

## 9. Resume bullets (templates)

- Assessed a simulated 85-user organisation against **CIS Controls v8.1 IG1** (56 safeguards), raising evidenced implementation from **X% to Y%**, and delivered a costed **90-day roadmap** and a "State of IT" presentation to management.
- Introduced **ITIL-style change management** (standard/normal/emergency, CAB, risk-assessed RFCs, change calendar) and an **IT policy pack of 10 policies**. Logged **N changes** with a **Z% success rate**, and linked config drift detection to change records.
- Built an automated **monthly IT KPI report** (Power BI; 14 KPIs across identity, patching, vulnerabilities, backup, service desk and change) and a consolidated risk register and action tracker, closing **N% of actions on time**.

## 10. Interview talking points

- **"How would you report IT to non-technical management?"** Business objectives → KPIs → RAG → the risks that need a decision. Show a page of the monthly report.
- **"Tell me about a process you improved."** JML (P2) or change management: before, after, measured effect, how you got buy-in.
- **"How do you prioritise with limited budget?"** CIS IG1 as a baseline, risk register scoring, a costed roadmap, and letting management make risk decisions with clear information.

## 11. AI-ready build prompt

```text
Act as an experienced IT manager / governance lead mentoring me through the final capstone.
Project: P10 IT Governance Capstone for fictional "Halden Distribution Ltd" (85 staff), which ties together my
P1-P9 homelab projects (AD, JML/MFA, AD hardening, endpoint baseline, patch/vuln mgmt, network/VPN, Wazuh SIEM/IR,
backup/DR, GLPI ITSM + docs + config drift detection). I will paste my project outputs/metrics as needed.

Phase by phase:
0. 1-page IT context: business objectives and the KPIs that support them.
1. CIS Controls v8.1 IG1 assessment workbook (all 56 safeguards; remind me to check the official list),
   before/after scoring rules (0-3, evidence required), mapping to my P1-P9 artifacts, charts, NIST CSF 2.0 summary.
2. Change management procedure (standard/normal/emergency), RFC template with risk checklist, CAB agenda and minutes
   template, change calendar with freeze periods, 3 worked example changes, change KPIs, drift-detection loop.
3. Ten short policies/standards (1-2 pages each, plain English) + acknowledgement process + exceptions register.
4. Collect-ITKpis script design, KPI definitions table, Power BI/Excel dashboard layout, 2-page monthly report
   template, risk register and consolidated action tracker templates.
5. 12-slide "State of IT" deck (content per slide, speaker notes) + costed 90-day roadmap + 10-minute talk script.
6. Portfolio packaging: landing README, 1-page results sheet, LinkedIn post series plan, resume Projects section.
Keep everything concise, honest (lab/simulated data clearly labelled) and management-friendly. Start with Phase 0.
```
