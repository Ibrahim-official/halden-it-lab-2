# Candidate Fit and Tailored Roadmap: Muhammad Ibrahim Akmal

**Based on:** current CV (Sep 2026) + the IT Support Officer and System Administrator job ads
**Goal:** get from "data and IT support" to "hireable for both roles", with evidence, in about 18 weeks part-time. Start applying from week 6.

---

## 1. Where you stand today

**Profile in one line:** final-year BSc Computer Science student (Virtual University, semester 7) with 6 months of paid experience (ChamStore, Apr 2026–present) in data management, workflow automation, internal tracking systems and general computer support. Programming: PHP/Laravel, SQL/MySQL, Python, C++.

### Gap analysis against both job ads

| Job ad requirement | Evidence you have now | Level | Project that closes the gap |
|---|---|---|---|
| Bachelor's in IT/CS/Engineering | BSc CS, semester 7 | 🟢 Meets (add expected graduation date) | — |
| Analytical, problem-solving | Data auditing, fixing duplicates/mismatches | 🟢 Strong | — |
| Reports, presentations, documentation | MS Office, reporting for non-technical staff | 🟢 Strong | P10 turns this into IT reporting |
| Accurate records, timely completion | Large-scale record keeping, tracking systems | 🟢 Strong | P9 turns this into a CMDB/helpdesk |
| Process improvement | Automation workflows that cut manual entry | 🟡 Good, but no numbers yet | P2, P10 (+ add numbers to ChamStore bullets) |
| Work across departments, follow up on actions | Tracking systems "across teams" | 🟡 Partial | P2 access reviews, P8 BIA, P10 action tracker |
| Technical support and escalation | General computer support to non-technical staff | 🟡 Partial | P9 (helpdesk, KB, escalation matrix) |
| Windows/Linux servers, AD, DNS, DHCP, file services | None on CV | 🔴 Gap | **P1** |
| Accounts, groups, MFA, least privilege | None | 🔴 Gap | **P2**, P3 |
| Monitoring, logs, alerts, security events | None | 🔴 Gap | **P7** |
| Endpoint protection, patching, hardening | None | 🔴 Gap | **P4**, **P5** |
| Backups, recovery, DR | None | 🔴 Gap | **P8** |
| Firewall, network, VPN, Wi-Fi | Computer Networks coursework only | 🔴 Gap | **P6** |
| Incidents, vulnerabilities, unauthorized access | None | 🔴 Gap | P3, P5, P7 |
| Inventory, configs, diagrams, technical docs | Tracking systems (non-IT) | 🟡 Transferable | P9 |
| Vendor coordination | None | 🔴 Gap | P9 vendor register |
| Security policies, change control | None | 🔴 Gap | P10 |

**Summary:** you already cover most of the **IT Support Officer** ad (business and records side). The **System Administrator** ad is where nearly all the gaps are. That's normal for a final-year student, and it's exactly what the 10 projects are for.

### Strengths to lean on

Your data, PHP/SQL and Python background gives you a real advantage in several projects. Most sysadmin candidates can't do these parts well:

| Your strength | Where it helps |
|---|---|
| Excel / Google Sheets at scale, data cleaning | P2 (the HR CSV is the source of truth, and data quality is the hardest part), P9 (asset reconciliation), P10 (KPI dashboard) |
| Automation workflows | P2 (JML automation), P5 (patching), P9 (config-as-code) |
| **PHP + MySQL** | **P9: GLPI is written in PHP on MySQL/MariaDB.** You can read its code, use its API, and write integrations most applicants can't |
| **Python** | **P5: the KEV/EPSS prioritization engine is Python + pandas**, your home ground |
| SQL | P9 GLPI reporting queries, P10 KPI data pipeline |
| Reporting for non-technical staff | Every project's business layer, plus P10's monthly report and "State of IT" deck |

**New skill to add first: PowerShell.** It's in almost every project. Your PHP/Python background means you'll pick it up quickly. Spend the first 3–4 days of P1 on Microsoft Learn's free PowerShell modules.

---

## 2. Tailored project order

The original order in `00-research-and-selection.md` follows pure technical dependencies. For you, the order is adjusted so you can **start applying early** with the projects that suit your strengths and the IT Support Officer role.

| # | Project | Weeks (part-time, ~8–10 h/wk) | Why here |
|---|---|---|---|
| 1 | **P1** Core Infrastructure | 1–2 | Foundation; closes the biggest gap (AD/DNS/DHCP/Windows + Linux) |
| 2 | **P2** Identity Lifecycle & MFA | 3–4 | CSV-driven automation plays to your data skills; MFA and least privilege are in the SysAdmin ad |
| 3 | **P9** Service Desk, CMDB & Docs | 5–6 | **Moved up.** GLPI = PHP/MySQL (your stack); your tracking-systems experience maps directly; it's the core of an IT Support Officer's job |
| 🎯 | **Milestone A: start applying** | end of week 6 | Target IT Support Officer, IT Officer, Helpdesk/Service Desk, Junior IT Admin roles |
| 4 | **P3** AD Security & Privileged Access | 7–8 | Builds on P1/P2 while they're fresh |
| 5 | **P4** Endpoint Hardening & Win11 Readiness | 9 | Needs P3 (LAPS, tiering) |
| 6 | **P8** Backup & DR | 10–11 | **Moved up.** Backups are in almost every sysadmin ad and interview |
| 🎯 | **Milestone B: apply for junior sysadmin roles** | end of week 11 | Target System Administrator (junior), IT Infrastructure Officer, NOC/IT Operations |
| 7 | **P5** Patch & Vulnerability Mgmt | 12–13 | Python prioritization engine = your standout project |
| 8 | **P6** Network, VPN & Wi-Fi | 14–15 | Builds on your Computer Networks coursework |
| 9 | **P7** SIEM & Incident Response | 16–17 | Needs the most RAM; best done once everything else exists |
| 10 | **P10** Governance & Reporting | 18 | Your reporting strength; ties the whole portfolio together |

### Adjustments needed because of the new order

- **P9 early:** build GLPI, the helpdesk, asset discovery, BookStack and config-as-code now, and add to the documentation after each later project. **Install Uptime Kuma in P9** (it's in P7 Phase 5 in the plan) so P8 can use its backup heartbeat.
- **P8 before P5–P7:** keep BKP01 non-domain-joined as planned. Put it on the existing LAN for now, then move it into the MGMT VLAN when you do P6. Add the Wazuh agent to BKP01 in P7.
- **M365 trial timing:** the free Business Premium trial lasts 30 days. **Start it on the day you reach P2 Phase 3**, not before, and finish all cloud work (Cloud Sync, Conditional Access, ScubaGear) inside that window. If you need cloud access later (the P6 NPS MFA extension), plan a second trial or use the TOTP fallback described in P6.

---

## 3. Lab setup for your situation

| Option | What works |
|---|---|
| **32 GB RAM PC** (recommended) | Everything, as in the plans |
| **16 GB RAM PC** (workable) | P1–P5, P8, P9, P10 if you **only run the VMs a phase needs**. Use Windows Server **Core** (no desktop) for DC02 and FS01 to save about 1 GB each. For P7, power off FS01/WS02/OPS01 while Wazuh runs, or give Wazuh 6 GB and accept slower dashboards |
| **Upgrade path** | Used business desktops and mini-PCs (Dell OptiPlex, HP EliteDesk, Lenovo ThinkCentre) are common on the local used market. A 32 GB RAM upgrade usually costs much less than a new machine; check DDR4 prices first |
| **No suitable PC** | **Azure for Students** (free credit, no credit card, needs your student email) can host a few VMs. Credits run out fast if VMs are left on, so **shut them down after each session** and set a budget alert. Use it for P1–P2 to start while you arrange hardware |

**Internet / power:** evaluation ISOs are 5–6 GB each, so download them all in week 1. **Snapshot before each phase.** If load-shedding cuts power, VMs can corrupt, so a UPS for the lab PC is worth it if you have frequent outages.

---

## 4. Use it for your final-year project

You're in semester 7, so your **Final Year Project (FYP)** is coming up. Ask your supervisor whether a student-proposed project is allowed. If it is, two options fit the programme well and double as portfolio pieces:

1. **"Risk-Based Vulnerability Prioritization System"** (from P5): Python engine + web dashboard (Laravel) that combines scanner output with CISA KEV, FIRST EPSS, asset exposure and criticality. It has a clear problem statement, a data model, algorithms and an evaluation.
2. **"SMB IT Operations Platform"** (from P9 + P10): Laravel app that pulls GLPI, Wazuh and backup-test data via APIs into a management KPI dashboard with RAG status and a CIS IG1 scorecard.

Both use your PHP/SQL/Python stack and produce a sysadmin-relevant result. Check VU's FYP requirements and deadlines with your supervisor.

---

## 5. Certifications (optional)

Projects are the priority because they're free and prove more. If you want one credential for your CV, in order of value for these two roles:

| When | Certification | Why |
|---|---|---|
| During P1–P2 (free) | **Microsoft Learn** training paths for Windows Server Hybrid Administrator (AZ-800) | Free learning that matches P1–P3. Add "Microsoft Learn: Windows Server Hybrid Administration path (in progress)" to your CV |
| After Milestone B | **Microsoft Certified: Windows Server Hybrid Administrator Associate** (AZ-800 + AZ-801) *or* **CCNA** | AZ-800/801 fits the SysAdmin ad most directly. CCNA is common in local networking and sysadmin job ads. Check current exam prices in PKR and any student discounts |
| Later | CompTIA Security+ | Broad security baseline, recognised internationally |

Free supporting courses: Cisco Networking Academy intro courses, Google IT Support Professional Certificate (Coursera offers financial aid).

---

## 6. Resume bullets for you, by project (fill in real numbers)

These replace the generic templates in each plan. They're written for a **"Projects / Home Lab"** section, in the order you'll build them.

**P1: Enterprise Active Directory Lab (Windows Server 2025, Ubuntu)**
- Built a redundant Active Directory environment for a simulated 85-user company (2 domain controllers, DNS, DHCP failover, DFS file shares); tested failover by shutting down the primary DC.
- Applied least-privilege (AGDLP) share permissions and verified them with a PowerShell audit script (0 direct user permissions); joined Ubuntu servers to AD with group-based SSH/sudo.

**P2: Automated User Lifecycle & MFA**
- Automated joiner/mover/leaver account management from an HR CSV (PowerShell), cutting leaver access removal from days to under **[N] minutes**, with dry-run mode, an audit log, and a safety check that blocks mass changes from bad data.
- Synced AD to Microsoft Entra ID and enforced MFA for 100% of users with Conditional Access; ran CISA's ScubaGear baseline check (**[X] → [Y]** passing checks).

**P9: IT Service Desk & Asset Inventory (GLPI, PHP/MySQL)**
- Deployed GLPI with automatic asset discovery for **[N]** devices (100% reconciled against network scans), a helpdesk with SLAs, an L1/L2/vendor escalation matrix, and **[N]** knowledge-base articles.
- Automated nightly backups of server and firewall configurations to Git, with alerts when a change has no approved change record.

**P3: Active Directory Security Assessment**
- Audited AD with PingCastle and BloodHound, fixed **[N]** findings (admin tiering, Windows LAPS, service-account hardening), and reduced the risk score from **[X] to [Y]**.

**P4: Endpoint Hardening & Windows 11 Readiness**
- Hardened Windows 11 with Microsoft security baselines, Defender attack-surface rules, BitLocker and LAPS (CIS compliance **[X]% → [Y]%**); produced a costed Windows 10 replacement report for management.

**P8: Backup & Disaster Recovery**
- Implemented 3-2-1-1-0 backups with an immutable copy and automated weekly restore tests (**[N]/[N]** passed); ran a timed ransomware recovery drill (**[X] min** vs **[Y] h** target).

**P5: Risk-Based Vulnerability Management (Python)**
- Built a Python engine that ranks vulnerability-scan findings using CISA KEV and FIRST EPSS data, reducing **[N]** findings to **[M]** urgent actions; set up ring-based Windows patching and Ansible Linux patching (**[X]%** compliance within 14 days).

**P6: Network Segmentation & VPN**
- Split a flat network into 6 firewall-controlled VLANs (OPNsense) and confirmed the rules with an automated nmap test (**[N]/[N]** as expected); replaced exposed RDP with an MFA-protected, AD-integrated VPN.

**P7: Security Monitoring & Incident Response**
- Deployed Wazuh SIEM with 12 custom detections for AD attacks, validated with Atomic Red Team (**[X]/[Y]** detected); wrote 5 incident playbooks and ran a ransomware tabletop exercise.

**P10: IT Governance & Management Reporting**
- Measured the environment against CIS Controls IG1 (**[X]% → [Y]%**), introduced change management and 10 IT policies, and built a monthly Power BI KPI report and a management presentation.

**Rules:** only add a bullet once that project is finished; replace every `[N]`/`[X]` with your real number; link the GitHub repo. Keep 4–6 of the strongest bullets on the CV and put the rest on the portfolio page.

---

## 7. Week-by-week start (first 2 weeks)

| Day | Task |
|---|---|
| 1 | Fix the CV now (see `02-cv-revised-draft.md`). Create a GitHub account/repo `halden-it-lab`. Download ISOs |
| 2–3 | Install Proxmox (or Hyper-V) and OPNsense. Microsoft Learn: PowerShell basics |
| 4–5 | P1 Phase 0 (design doc) → Phase 1 (DC01) |
| 6–8 | P1 Phases 2–4 (DC02, DHCP failover, users/groups from CSV) |
| 9–11 | P1 Phases 5–7 (file services, GPO, Linux join) |
| 12–14 | P1 Phase 8 (docs + diagram), README, first LinkedIn post |

Use the AI prompt at the end of `P01-core-infrastructure-build.md` to be guided phase by phase.
