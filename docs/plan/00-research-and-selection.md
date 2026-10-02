# IT Support Officer + System Administrator: Capstone Project Portfolio

**Research, 50-idea longlist, scoring, and the final top 10**
Prepared: 29 Sep 2026

---

## 1. What the two job ads actually want

The two roles overlap, but each weights things differently. A candidate who covers both is someone who **runs infrastructure competently and can explain it to the business**: write the report, walk management through the risk, chase the follow-up, keep the records clean.

| Theme | IT Support Officer (business-facing) | System Administrator (technical) |
|---|---|---|
| Operations | Understand operations, policies, processes; support daily admin | Administer Windows/Linux, AD, DNS, DHCP, file services |
| Identity | Not stated | Accounts, groups, permissions, MFA, least privilege |
| Security | Identify operational issues, escalate to management | Monitoring, logs, alerts, incidents, vulnerabilities, hardening |
| Resilience | Not stated | Backups, recovery, DR, periodic backup verification |
| Network | Not stated | Firewall, VPN, Wi-Fi, infrastructure |
| Records | Maintain accurate records, timely completion | Inventory, configurations, diagrams, technical docs |
| Communication | Reports, presentations, business updates | Vendor coordination, escalation support to IT Support team |
| Process | Process improvement, business projects, follow-up on actions | Change control, access-management standards, IT policies |
| Mindset | Ownership, continuous learning, cross-department work | Security-first, documented, verified |

**Design principle for the portfolio:** every project has two layers.
1. **Technical layer**: builds and hardens something real (System Administrator ad).
2. **Business layer**: a short stakeholder brief, a management report or slide deck, a process document, and a tracked action list (IT Support Officer ad).

That is how one portfolio covers both ads. Almost no candidate shows the second layer, so it sets you apart.

---

## 2. Market research: the problems these projects solve

Evidence from current industry sources. The top 10 are built to address these specific pains.

| # | Market finding | What it means for the portfolio | Source |
|---|---|---|---|
| 1 | Credential abuse is the most common initial access vector (22% of breaches). Phishing is 16%. | Identity lifecycle, MFA and privileged access are the top priority (P2, P3). | [Verizon 2025 DBIR](https://www.verizon.com/about/news/2025-data-breach-investigations-report) |
| 2 | Ransomware appears in 44% of breaches overall and **88% of SMB breaches**. | Backups, hardening, segmentation and detection are the core SMB needs (P4, P6, P7, P8). | [Verizon 2025 DBIR](https://www.verizon.com/about/news/2025-data-breach-investigations-report), [DBIR SMB snapshot](https://www.verizon.com/business/resources/infographics/2025-dbir-smb-snapshot.pdf) |
| 3 | Exploitation of vulnerabilities rose 34%, focused on **edge devices and VPNs**. Third-party involvement doubled to 30%. | Vulnerability prioritization (P5), VPN/firewall hardening (P6), vendor register (P9). | [Verizon 2025 DBIR](https://www.verizon.com/about/news/2025-data-breach-investigations-report) |
| 4 | MFA cut account-compromise risk by **99.22%** (98.56% even for leaked credentials) in Microsoft's peer-reviewed study. | MFA and Conditional Access are the highest-ROI control to show (P2). | [Microsoft research paper (arXiv 2305.00945)](https://arxiv.org/pdf/2305.00945) |
| 5 | Attackers go after backup repositories in almost every ransomware attack (Veeam: 96% targeted, 76% of those succeed). | Immutable and offline backups plus **tested** restores (P8). "Periodically verify backups" appears in the ad for this reason. | [Veeam Ransomware Trends](https://recovery.cyberfortress.com/hubfs/Veeam%20Documents/ransomware-trends_v2.pdf), [Varonis stats roundup](https://www.varonis.com/blog/ransomware-statistics) |
| 6 | CISA **BOD 26-04** (June 2026) replaced flat patch deadlines with risk tiers: exposure, KEV status, automatable exploit, technical impact. Top-tier fixes are due in 3 days. | Using a 2026 federal prioritization model in your own patch program is a strong, current talking point (P5). | [CISA BOD 26-04](https://www.cisa.gov/news-events/directives/bod-26-04-prioritizing-security-updates-based-risk), [Industrial Cyber summary](https://industrialcyber.co/cisa/cisa-bod-26-04-directs-agencies-to-prioritize-exploited-vulnerabilities-and-assess-compromise-before-patching/) |
| 7 | About 21% of SMB Windows devices still ran **Windows 10** in mid-2026, after support ended on 14 Oct 2025. | A Windows 11 readiness and ESU risk report is exactly what an SMB IT officer gets asked for (P4). | [Computer Weekly / Lansweeper](https://www.computerweekly.com/news/366645847/A-fifth-of-PC-devices-still-on-Windows-10), [Microsoft ESU](https://learn.microsoft.com/en-us/windows/whats-new/extended-security-updates) |
| 8 | Offboarding is a known weak point. Only about 44% of companies revoke all access within 24 hours (vendor survey). | Joiner-Mover-Leaver automation with an audit trail (P2). | [Newployee offboarding stats](https://www.newployee.com/blog/employee-offboarding-statistics-for-2026) *(vendor-compiled, treat as directional)* |
| 9 | Many SMBs track IT assets on spreadsheets or not at all. Outdated records are a common complaint. | CMDB/asset inventory with automated discovery (P9). | [ITSM.tools](https://itsm.tools/itsm-maturity/), [Cinch IT](https://cinchit.com/smb-it-asset-inventory/) *(vendor blogs, directional)* |
| 10 | **CIS Controls v8.1 IG1** (56 safeguards) is described as the emerging minimum standard for SMB cyber hygiene. | Use IG1 as the measuring stick for the whole portfolio, with before and after scores (P10). | [CIS IG1](https://www.cisecurity.org/controls/implementation-groups/ig1) |
| 11 | CISA's free **ScubaGear** tool checks a Microsoft 365 tenant against the SCuBA baselines. Maester adds Pester-based tests. | Free, credible, report-generating proof for cloud identity work (P2). | [ScubaGear](https://github.com/cisagov/ScubaGear) |
| 12 | Hiring managers want receipts: documented builds, GPO configs, PowerShell automation, verification screenshots. Hybrid AD + Entra ID is now the normal Windows admin environment. | Every project ships a GitHub repo with configs, scripts, screenshots and a before/after metric. | [Example AD homelab repo](https://github.com/mattwboyd/active-directory-homelab), [Wazuh AD detection](https://wazuh.com/blog/how-to-detect-active-directory-attacks-with-wazuh-part-1-of-2/) |

---

## 3. The lab scenario (one company for all 10 projects)

All ten projects run inside **one fictional company**, so they build on each other and add up to a single story you can tell in an interview.

> **Halden Distribution Ltd.** (fictional): 85 staff, one head office, one warehouse, 12 remote sales staff.
> Departments: Management, Finance, HR, Sales, Operations/Warehouse, IT (you).
> Situation you inherit: flat network, shared admin passwords, no MFA, ad-hoc backups nobody has tested, assets tracked in a spreadsheet, tickets arriving by email and WhatsApp, 30% of PCs on Windows 10.

**AD domain:** `ad.halden.internal`. `.internal` is the TLD ICANN reserved for private use in 2024; say so in interviews.

### Lab hardware and software (low-cost)

| Item | Recommendation | Cost |
|---|---|---|
| Host | Any PC or mini-PC, **32 GB RAM minimum (64 GB ideal)**, 1 TB SSD | What you already have, or a used mini-PC |
| Hypervisor | Proxmox VE (free), or Hyper-V on Windows 11 Pro | Free |
| Windows Server 2025 | 180-day evaluation ISO | Free |
| Windows 11 Enterprise | 90-day evaluation ISO | Free |
| Linux | Ubuntu Server 24.04 LTS, optionally Rocky Linux 9 | Free |
| Firewall | OPNsense or pfSense CE | Free |
| Cloud identity | Microsoft 365 Business Premium 1-month trial, or an Entra ID Free tenant. The M365 Developer Program sandbox is now limited to qualifying subscribers, so don't count on it. | Free for 30 days. Plan P2 cloud work inside that window. |
| Open-source tools | Wazuh, Greenbone/OpenVAS, GLPI, BookStack, Uptime Kuma, restic, MinIO, PingCastle | Free |

**VM plan (about 31 GB if everything runs at once; power off what you're not using):**
`FW01` (OPNsense, 1 GB) · `DC01` + `DC02` (Server 2025, 4 + 2 GB) · `FS01` (file server, 2 GB) · `WS01`/`WS02` (Win 11, 4 GB each) · `LNX01` (Ubuntu app server, 2 GB) · `SIEM01` (Wazuh, 8 GB) · `OPS01` (GLPI/BookStack/Uptime Kuma, 4 GB) · `BKP01` (restic + MinIO, 2 GB)

**Evaluation timing:** Server evals last 180 days and Windows 11 evals last 90. Build the full sequence in about 12–16 weeks and snapshot everything.

---

## 4. The 50-idea longlist and scoring

**Scoring model** (each criterion scored 1–5, weighted to a total out of 100):

| Criterion | Weight | Question |
|---|---|---|
| **F**: JD fit | ×6 | How many bullets across *both* ads does it prove? |
| **P**: Market pain | ×4 | Does it solve a documented, current problem (Section 2)? |
| **R**: Resume proof | ×4 | Does it produce a measurable before/after result and visible artifacts? |
| **E**: Feasibility | ×3 | Can it be built free or cheap in 1–3 weeks part-time? |
| **D**: Differentiation | ×3 | Does it stand out from the standard "I built AD" homelab? |

**Decision key:** **SELECTED** = anchor of a top-10 project · **Merged → Pn** = folded into a top-10 project as a component · **Rejected** = scored too low or poor fit.

### A. Identity and access

| # | Idea | F | P | R | E | D | Score | Decision |
|---|---|---|---|---|---|---|---|---|
| 1 | AD DS core build: OU design, AGDLP groups, DNS, DHCP failover, file services, GPO baseline | 5 | 4 | 4 | 5 | 3 | 86 | **SELECTED → P1** |
| 2 | Joiner-Mover-Leaver automation from an HR CSV (PowerShell), with audit log | 5 | 5 | 5 | 4 | 4 | 94 | **SELECTED → P2** |
| 3 | Hybrid identity: Entra Connect/Cloud Sync + MFA + Conditional Access + ScubaGear report | 5 | 5 | 4 | 3 | 4 | 87 | Merged → P2 |
| 4 | Quarterly access review / recertification report for department heads | 4 | 4 | 4 | 5 | 3 | 80 | Merged → P2 |
| 5 | Privileged access tiering (Tier 0/1/2), Windows LAPS, Protected Users, admin workstations | 5 | 5 | 4 | 4 | 4 | 90 | Merged → P3 |
| 6 | AD security assessment with PingCastle/Purple Knight, remediated and re-scored | 5 | 4 | 5 | 5 | 4 | 93 | **SELECTED → P3** |
| 7 | Self-service password reset portal | 3 | 3 | 3 | 3 | 2 | 57 | Rejected |
| 8 | Stale/orphaned account detection and cleanup script | 4 | 5 | 4 | 5 | 2 | 81 | Merged → P2 |
| 9 | SAML SSO for SaaS apps via Entra ID | 3 | 3 | 3 | 3 | 3 | 60 | Rejected (licence-bound) |
| 10 | Fine-grained password policies + banned-password list | 4 | 3 | 3 | 5 | 2 | 69 | Merged → P3 |

### B. Endpoints and patching

| # | Idea | F | P | R | E | D | Score | Decision |
|---|---|---|---|---|---|---|---|---|
| 11 | CIS / Microsoft Security Baseline GPO hardening + compliance report | 5 | 4 | 5 | 4 | 3 | 87 | **SELECTED → P4** |
| 12 | Windows 11 migration readiness assessment and Windows 10 ESU risk report | 4 | 5 | 4 | 4 | 4 | 84 | Merged → P4 |
| 13 | BitLocker rollout with recovery keys escrowed to AD | 4 | 3 | 3 | 5 | 2 | 69 | Merged → P4 |
| 14 | Defender Attack Surface Reduction rules, audit then block | 4 | 4 | 4 | 4 | 4 | 80 | Merged → P4 |
| 15 | WSUS patch rings (pilot/broad) with a compliance dashboard | 5 | 5 | 4 | 4 | 3 | 87 | Merged → P5 |
| 16 | Vulnerability scanning (Greenbone) + KEV/EPSS/BOD 26-04 risk prioritization | 5 | 5 | 5 | 4 | 5 | 97 | **SELECTED → P5** |
| 17 | Linux patch automation with Ansible / unattended-upgrades | 4 | 3 | 4 | 4 | 3 | 73 | Merged → P5 |
| 18 | Application allow-listing (AppLocker/WDAC) | 3 | 3 | 3 | 3 | 4 | 63 | Rejected (stretch goal in P4) |
| 19 | Intune + Autopilot zero-touch provisioning | 3 | 4 | 4 | 2 | 4 | 68 | Rejected (licence and time) |
| 20 | MDT/WDS imaging server | 3 | 2 | 3 | 4 | 1 | 53 | Rejected (outdated approach) |

### C. Network and perimeter

| # | Idea | F | P | R | E | D | Score | Decision |
|---|---|---|---|---|---|---|---|---|
| 21 | OPNsense VLAN segmentation (users/servers/mgmt/guest/IoT) | 5 | 4 | 4 | 4 | 3 | 83 | Merged → P6 |
| 22 | WireGuard remote-access VPN with per-group rules | 5 | 5 | 4 | 4 | 3 | 87 | **SELECTED → P6** |
| 23 | 802.1X WPA2/WPA3-Enterprise Wi-Fi with NPS (RADIUS) against AD | 5 | 3 | 4 | 3 | 4 | 79 | Merged → P6 |
| 24 | Firewall rule-base review and cleanup with a documented matrix | 4 | 4 | 4 | 4 | 3 | 77 | Merged → P6 |
| 25 | DNS filtering (AdGuard Home/Quad9 forwarders) | 3 | 3 | 3 | 5 | 2 | 63 | Merged → P6 (small add-on) |
| 26 | IPAM + network source of truth (NetBox) | 4 | 3 | 3 | 5 | 3 | 72 | Merged → P9 |
| 27 | Suricata IDS on the perimeter | 3 | 3 | 3 | 3 | 3 | 60 | Rejected (stretch goal in P7) |

### D. Monitoring and incident response

| # | Idea | F | P | R | E | D | Score | Decision |
|---|---|---|---|---|---|---|---|---|
| 28 | Wazuh SIEM + Sysmon + AD attack detections, validated with Atomic Red Team | 5 | 5 | 5 | 4 | 4 | 94 | **SELECTED → P7** |
| 29 | Availability monitoring (Uptime Kuma / Zabbix) with alert routing | 5 | 4 | 4 | 5 | 2 | 83 | Merged → P7 |
| 30 | Incident response playbooks + a tabletop exercise with management | 5 | 4 | 4 | 5 | 4 | 89 | Merged → P7 |
| 31 | Central log retention (Graylog / rsyslog) | 4 | 3 | 3 | 4 | 2 | 66 | Rejected (Wazuh covers it) |
| 32 | Honeypots / canary tokens | 3 | 2 | 3 | 5 | 4 | 65 | Rejected (stretch goal in P7) |
| 33 | Phishing simulation (GoPhish) + awareness training | 3 | 4 | 4 | 4 | 3 | 71 | Rejected (optional bonus) |
| 34 | Email authentication audit (SPF/DKIM/DMARC) | 3 | 5 | 4 | 5 | 3 | 78 | Rejected (needs a real domain; good bonus) |

### E. Backup and disaster recovery

| # | Idea | F | P | R | E | D | Score | Decision |
|---|---|---|---|---|---|---|---|---|
| 35 | 3-2-1-1-0 backup with an immutable copy + **automated restore testing** | 5 | 5 | 5 | 4 | 5 | 97 | **SELECTED → P8** |
| 36 | DR runbook, business impact analysis with departments, measured RTO/RPO | 5 | 5 | 5 | 4 | 4 | 94 | Merged → P8 |
| 37 | AD forest recovery drill (restore a DC, seize FSMO roles) | 4 | 4 | 4 | 3 | 5 | 80 | Merged → P8 |
| 38 | Microsoft 365 mailbox/OneDrive backup | 3 | 4 | 3 | 3 | 2 | 61 | Rejected (licence-bound) |

### F. Documentation, assets and vendors

| # | Idea | F | P | R | E | D | Score | Decision |
|---|---|---|---|---|---|---|---|---|
| 39 | Asset inventory / CMDB (GLPI) with agent-based automated discovery | 5 | 5 | 4 | 5 | 3 | 90 | **SELECTED → P9** |
| 40 | IT documentation wiki (BookStack) with as-built docs and diagrams | 5 | 4 | 4 | 5 | 2 | 83 | Merged → P9 |
| 41 | Vendor, contract and licence register with renewal alerts | 4 | 4 | 3 | 5 | 3 | 76 | Merged → P9 |
| 42 | Config-as-code: GPO/firewall config backups versioned in Git | 4 | 3 | 4 | 4 | 4 | 76 | Merged → P9 |
| 43 | Linux server joined to AD (realmd/SSSD), SSH hardening, sudo via AD groups | 5 | 3 | 4 | 4 | 3 | 79 | Merged → P1 |

### G. Service management and business operations (IT Support Officer layer)

| # | Idea | F | P | R | E | D | Score | Decision |
|---|---|---|---|---|---|---|---|---|
| 44 | Helpdesk with SLAs, categories, knowledge base, escalation matrix | 5 | 4 | 4 | 5 | 2 | 83 | Merged → P9 (GLPI does both) |
| 45 | Change management: RFC template, CAB workflow, change calendar | 5 | 3 | 4 | 5 | 3 | 82 | Merged → P10 |
| 46 | Monthly IT operations KPI dashboard + management report | 5 | 4 | 5 | 5 | 4 | 93 | Merged → P10 |
| 47 | IT policy pack (acceptable use, access control, backup, patch, change) | 4 | 4 | 3 | 5 | 2 | 73 | Merged → P10 |
| 48 | Department process mapping, e.g. new-starter request → ticket → provisioning | 5 | 4 | 4 | 4 | 4 | 86 | Merged → P2 + P10 |
| 49 | **CIS Controls v8.1 IG1 gap assessment + 90-day roadmap for management** | 5 | 5 | 5 | 5 | 4 | 97 | **SELECTED → P10** |
| 50 | Licence right-sizing and IT cost-optimization report | 3 | 4 | 4 | 4 | 3 | 71 | Rejected (bonus section in P10) |

**Why ideas got merged instead of standing alone:** a hiring manager remembers **10 strong projects** better than 25 thin ones. Ideas that share a lab component or a business outcome were combined, so each final project is a complete piece of work.

---

## 5. The final top 10 (in build order)

Build order follows dependencies: each project uses what the earlier ones created.

| # | Project | Anchor score | Main JD bullets proven | Time (part-time) |
|---|---|---|---|---|
| **P1** | [Core Infrastructure Build: AD DS, DNS, DHCP, file services, GPO, Linux integration](./P01-core-infrastructure-build.md) | 86 | Windows/Linux, AD, DNS, DHCP, file services, documentation | 2 weeks |
| **P2** | [Identity Lifecycle and Access Governance: JML automation, MFA, Conditional Access, access reviews](./P02-identity-lifecycle-access-governance.md) | 94 | Accounts, groups, MFA, least privilege, process improvement, cross-department | 2 weeks |
| **P3** | [AD Security Assessment and Privileged Access Hardening](./P03-ad-security-assessment-privileged-access.md) | 93 | Hardening, vulnerabilities, unauthorized access, security checks | 1.5 weeks |
| **P4** | [Endpoint Hardening Baseline and Windows 11 Readiness](./P04-endpoint-hardening-win11-readiness.md) | 87 | Endpoint protection, hardening, reports to management | 1.5 weeks |
| **P5** | [Risk-Based Patch and Vulnerability Management Program](./P05-patch-vulnerability-management.md) | 97 | Patching, updates, vulnerability remediation, security checks | 2 weeks |
| **P6** | [Network Segmentation, Remote-Access VPN and Enterprise Wi-Fi](./P06-network-segmentation-vpn-wifi.md) | 87 | Firewall, network, VPN, Wi-Fi, diagrams | 2 weeks |
| **P7** | [Security Monitoring, SIEM and Incident Response](./P07-monitoring-siem-incident-response.md) | 94 | System health, logs, alerts, security events, incident response | 2 weeks |
| **P8** | [Backup, Recovery and DR with Automated Restore Verification](./P08-backup-dr-restore-verification.md) | 97 | Backup, recovery, DR procedures, periodic verification | 2 weeks |
| **P9** | [IT Service Desk, Asset Inventory (CMDB) and Documentation Hub](./P09-service-desk-cmdb-documentation.md) | 90 | Inventory, configs, diagrams, docs, vendors, escalation support, records | 1.5 weeks |
| **P10** | [IT Governance Capstone: CIS IG1 Scorecard, Change Control and Management Reporting](./P10-governance-cis-ig1-change-reporting.md) | 97 | Reports, presentations, process improvement, policies, change control, management communication | 1.5 weeks |

**Total:** about 18 weeks part-time (8–10 hrs/week), or 8–10 weeks full-time.

### JD coverage check (every bullet from both ads is covered)

| JD bullet | Covered by |
|---|---|
| Windows/Linux servers, AD, DNS, DHCP, file services | P1, P3 |
| Accounts, permissions, groups, MFA, least privilege | P2, P3 |
| Monitor health, availability, logs, alerts, security events | P7 |
| Endpoint protection, patching, updates, backups, hardening | P4, P5, P8 |
| Firewall, network, VPN, Wi-Fi | P6 |
| Security incidents, vulnerabilities, unauthorized access | P3, P5, P7 |
| Backup, recovery, DR, periodic verification | P8 |
| Regular security checks, vulnerability remediation | P3, P5, P10 |
| Inventory, configurations, diagrams, documentation | P9 (plus docs in every project) |
| Vendor coordination | P9 (vendor register), P5 and P6 (vendor advisories), P8 (DR contacts) |
| Security policies, change control, access standards | P2, P10 |
| Technical support and escalation for the IT Support team | P9 |
| *Officer:* understand operations, policies, processes | P2 (process mapping), P8 (BIA), P10 |
| *Officer:* work with departments | P2 (access reviews), P8 (BIA interviews), P10 |
| *Officer:* reports, presentations, documentation, updates | Every project's business layer; P10 monthly report and deck |
| *Officer:* process improvement, business projects | P2, P9, P10 |
| *Officer:* coordinate, follow up on action items | P10 action tracker, P7 tabletop actions |
| *Officer:* accurate records, timely completion | P9 CMDB and SLAs, P10 change log |
| *Officer:* identify operational issues, communicate to management | P4, P5, P10 (risk register + monthly report) |

---

## 6. Rules that apply to every project

1. **Public GitHub repo per project** (or one monorepo with ten folders): `README.md` (problem → solution → result), `/scripts`, `/configs`, `/docs`, `/evidence` (redacted screenshots), `/business` (reports and slides).
2. **Before/after metric in every README.** A number, for example "PingCastle score 78 → 12" or "restore success verified weekly, RTO 42 min."
3. **Never commit secrets.** Use `.gitignore` and redact tenant IDs, IPs outside the lab and passwords. Run `gitleaks` before each push.
4. **Be honest on the resume.** Put these under **"Projects / Home Lab"**, not under employment. Interviewers respect a well-documented lab. Presenting a lab as job experience is a quick way to fail a technical interview.
5. **Write a short blog post or LinkedIn post per project.** It builds a public record and gives recruiters something to find.
6. **Snapshot VMs before each phase.** Rolling back is part of good change control, and you can mention it in interviews.

---

## 7. How to use the AI prompts in each plan

Each project file ends with an **AI-ready build prompt**. Paste it into Claude at the start of that project and it will act as a senior sysadmin mentor, taking you through the phases one at a time and checking your output. Paste your command output or screenshots back in as you go.

---

## Tailored to the candidate

The CV has been reviewed. See:
- [`01-candidate-fit-and-tailored-roadmap.md`](./01-candidate-fit-and-tailored-roadmap.md): gap analysis against both ads, adjusted project order with application milestones (week 6 and week 11), lab options for 16/32 GB RAM, final-year project ideas, certifications, and tailored resume bullets per project.
- [`02-cv-revised-draft.md`](./02-cv-revised-draft.md): what to fix in the current CV, and a revised draft.
- [`03-ai-agent-build-and-showcase-guide.md`](./03-ai-agent-build-and-showcase-guide.md): operating guide for the AI agent that builds each project and publishes it on the online CV website.
