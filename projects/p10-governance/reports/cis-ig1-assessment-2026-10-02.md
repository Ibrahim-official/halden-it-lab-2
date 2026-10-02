# Halden Distribution Ltd. — CIS Controls v8.1 IG1 self-assessment

> **Status of this report: template — no safeguards scored yet.** Halden Distribution Ltd. is a fictional 85-user company used for a home-lab portfolio. Every score in the table below is written by hand after the named evidence has actually been seen; a safeguard with no evidence stays blank rather than being scored generously.

**As of:** 2026-10-02  
**Scope:** all 56 CIS Controls v8.1 Implementation Group 1 safeguards  
**Scored so far:** 0 of 56 (after), 0 of 56 (before)  
**Owner:** IT Lead (Halden)  ·  **Review:** quarterly  

## 1. Method

Each safeguard is scored on the plan's four-point scale:

- **0** — Not implemented
- **1** — Partial
- **2** — Implemented on some systems
- **3** — Fully implemented and evidenced

A score of **3 requires evidence**: the assessment tool refuses to accept a 3 whose row has no evidence source. **Before** is the inherited Halden state recorded in each project's problem statement; **after** is the state today, counting only what has a file to prove it.

## 2. Headline result

**Not scored yet.** No safeguard carries a score, so the implementation percentage is deliberately not printed. The bar-chart template in `docs/diagrams/p10-cis-ig1-chart-template.svg` sits empty for the same reason: a percentage appears here only when the underlying scores exist.

## 3. Result by control

| Control | Name | IG1 safeguards | Scored (after) | Before % | After % |
|---|---|---|---|---|---|
| 1 | Inventory and Control of Enterprise Assets | 2 | 0 | not measured | not measured |
| 2 | Inventory and Control of Software Assets | 3 | 0 | not measured | not measured |
| 3 | Data Protection | 6 | 0 | not measured | not measured |
| 4 | Secure Configuration of Enterprise Assets and Software | 7 | 0 | not measured | not measured |
| 5 | Account Management | 4 | 0 | not measured | not measured |
| 6 | Access Control Management | 5 | 0 | not measured | not measured |
| 7 | Continuous Vulnerability Management | 4 | 0 | not measured | not measured |
| 8 | Audit Log Management | 3 | 0 | not measured | not measured |
| 9 | Email and Web Browser Protections | 2 | 0 | not measured | not measured |
| 10 | Malware Defenses | 3 | 0 | not measured | not measured |
| 11 | Data Recovery | 4 | 0 | not measured | not measured |
| 12 | Network Infrastructure Management | 1 | 0 | not measured | not measured |
| 14 | Security Awareness and Skills Training | 8 | 0 | not measured | not measured |
| 15 | Service Provider Management | 1 | 0 | not measured | not measured |
| 17 | Incident Response Management | 3 | 0 | not measured | not measured |

## 4. Safeguard detail

| Safeguard | Title | In scope | Before | After | Evidence source | Expected evidence (Halden) |
|---|---|---|---|---|---|---|
| 1.1 | Establish and Maintain Detailed Enterprise Asset Inventory | yes | not measured | not measured | — | GLPI asset inventory (P9) reconciled with a network scan and the DHCP/AD computer objects |
| 1.2 | Address Unauthorized Assets | yes | not measured | not measured | — | GLPI reconciliation run showing 0 unknown devices and the process note for quarantine |
| 2.1 | Establish and Maintain a Software Inventory | yes | not measured | not measured | — | GLPI software inventory export with publisher and version |
| 2.2 | Ensure Authorized Software is Currently Supported | yes | not measured | not measured | — | Windows 11 readiness report listing unsupported Windows 10 devices and the ESU/exception decision |
| 2.3 | Address Unauthorized Software | yes | not measured | not measured | — | GLPI software inventory with the unauthorised-software review column |
| 3.1 | Establish and Maintain a Data Management Process | yes | not measured | not measured | — | Data Protection section of the P10 policy pack (owner review date and exceptions process) |
| 3.2 | Establish and Maintain a Data Inventory | yes | not measured | not measured | — | GLPI asset/data inventory plus the permissions matrix showing Finance and HR data owners |
| 3.3 | Configure Data Access Control Lists | yes | not measured | not measured | — | AGDLP permission matrix and the PowerShell ACL audit reporting 0 violations |
| 3.4 | Enforce Data Retention | yes | not measured | not measured | — | Retention schedule in the P10 policy pack (Finance and HR retention periods) |
| 3.5 | Securely Dispose of Data | yes | not measured | not measured | — | Disposal and leaver-data-handling section of the P10 policy pack |
| 3.6 | Encrypt Data on End-User Devices | yes | not measured | not measured | — | BitLocker escrow proof - recovery key stored in AD and a successful recovery test |
| 4.1 | Establish and Maintain a Secure Configuration Process | yes | not measured | not measured | — | P1 GPO baseline plus the as-built document describing the build standard |
| 4.2 | Establish and Maintain a Secure Configuration Process for Network Infrastructure | yes | not measured | not measured | — | P6 firewall rule matrix and the network standard in the P10 policy pack |
| 4.3 | Configure Automatic Session Locking on Enterprise Assets | yes | not measured | not measured | — | Desktop standards GPO (secure screen saver 600s) evidenced by gpresult on WS01 |
| 4.4 | Implement and Manage a Firewall on Servers | yes | not measured | not measured | — | Segmentation test results showing server ports filtered by the firewall |
| 4.5 | Implement and Manage a Firewall on End-User Devices | yes | not measured | not measured | — | Host firewall baseline in the P4 security baseline and the compliance report |
| 4.6 | Securely Manage Enterprise Assets and Software | yes | not measured | not measured | — | P9 config-as-code (GPO and firewall configs versioned in Git) with the container compose file |
| 4.7 | Manage Default Accounts on Enterprise Assets and Software | yes | not measured | not measured | — | Windows LAPS GPO settings and the disabled built-in administrator account |
| 5.1 | Establish and Maintain an Inventory of Accounts | yes | not measured | not measured | — | P2 account inventory and the quarterly access review report |
| 5.2 | Use Unique Passwords | yes | not measured | not measured | — | Domain password and lockout GPO (14 character minimum) from the P1 baseline |
| 5.3 | Disable Dormant Accounts | yes | not measured | not measured | — | P2 dormant-account hygiene report (0 stale enabled accounts targeted) |
| 5.4 | Restrict Administrator Privileges to Dedicated Administrator Accounts | yes | not measured | not measured | — | P3 privileged access tiering model (Tier 0/1/2) with dedicated adm- accounts |
| 6.1 | Establish an Access Granting Process | yes | not measured | not measured | — | P1 runbook "Add a new Halden user" plus the P2 joiner automation |
| 6.2 | Establish an Access Revoking Process | yes | not measured | not measured | — | P2 leaver run: account disabled moved to Disabled OU and sessions revoked |
| 6.3 | Require MFA for Externally-Exposed Applications | yes | not measured | not measured | — | P2 MFA coverage report (Conditional Access enforced for all users) |
| 6.4 | Require MFA for Remote Network Access | yes | not measured | not measured | — | P6 VPN MFA prompt and the RADIUS/NPS decision note |
| 6.5 | Require MFA for Administrative Access | yes | not measured | not measured | — | P3 privileged access standard and the MFA-enforced admin sign-in proof |
| 7.1 | Establish and Maintain a Vulnerability Management Process | yes | not measured | not measured | — | Vulnerability Management section of the P10 policy pack |
| 7.2 | Establish and Maintain a Remediation Process | yes | not measured | not measured | — | P3 remediation priority rules and the P5 tiering decision record |
| 7.3 | Perform Automated Operating System Patch Management | yes | not measured | not measured | — | P5 WSUS ring patch compliance report (target 95% within 14 days) |
| 7.4 | Perform Automated Application Patch Management | yes | not measured | not measured | — | P5 application patch coverage from the same ring compliance report |
| 8.1 | Establish and Maintain an Audit Log Management Process | yes | not measured | not measured | — | Logging and Monitoring section of the P10 policy pack |
| 8.2 | Collect Audit Logs | yes | not measured | not measured | — | P7 Wazuh agents reporting and the enabled security audit policy |
| 8.3 | Ensure Adequate Audit Log Storage | yes | not measured | not measured | — | P7 Wazuh retention and index storage proof (90 days) |
| 9.1 | Ensure Use of Only Fully Supported Browsers and Email Clients | yes | not measured | not measured | — | P4 supported-browser baseline in the compliance report |
| 9.2 | Use DNS Filtering Services | yes | not measured | not measured | — | P6 DNS filtering (AdGuard Home/Quad9) client configuration proof |
| 10.1 | Deploy and Maintain Anti-Malware Software | yes | not measured | not measured | — | P4 Microsoft Defender status across the fleet in the compliance report |
| 10.2 | Configure Automatic Anti-Malware Signature Updates | yes | not measured | not measured | — | Defender signature update policy and last-update proof |
| 10.3 | Disable Autorun and Autoplay for Removable Media | yes | not measured | not measured | — | P4 baseline policy disabling autorun and autoplay |
| 11.1 | Establish and Maintain a Data Recovery Process | yes | not measured | not measured | — | P8 backup and DR design plus the Backup and Recovery section of the policy pack |
| 11.2 | Perform Automated Backups | yes | not measured | not measured | — | P8 weekly automated restore-test history |
| 11.3 | Protect Recovery Data | yes | not measured | not measured | — | P8 repository encryption and immutability proof |
| 11.4 | Establish and Maintain an Isolated Instance of Recovery Data | yes | not measured | not measured | — | P8 immutability deletion-refused proof for the isolated offsite copy |
| 12.1 | Ensure Network Infrastructure is Up-to-Date | yes | not measured | not measured | — | P5 firmware patching record for FW01/FW02 and the support review |
| 14.1 | Establish and Maintain a Security Awareness Program | yes | not measured | not measured | — | Gap: no awareness programme exists yet - tracked in the P10 90-day roadmap |
| 14.2 | Train Workforce Members to Recognize Social Engineering Attacks | yes | not measured | not measured | — | Gap - future phishing simulation and training register (roadmap item) |
| 14.3 | Train Workforce Members on Authentication Best Practices | yes | not measured | not measured | — | Gap - future training register (roadmap item) |
| 14.4 | Train Workforce on Data Handling Best Practices | yes | not measured | not measured | — | Gap - future training register (roadmap item) |
| 14.5 | Train Workforce Members on Causes of Unintentional Data Exposure | yes | not measured | not measured | — | Gap - future training register (roadmap item) |
| 14.6 | Train Workforce Members on Recognizing and Reporting Security Incidents | yes | not measured | not measured | — | Gap - future training register (roadmap item) |
| 14.7 | Train Workforce on How to Identify and Report if Their Enterprise Assets are Missing Security Updates | yes | not measured | not measured | — | Gap - future training register (roadmap item) |
| 14.8 | Train Workforce on the Dangers of Connecting to and Transmitting Enterprise Data Over Insecure Networks | yes | not measured | not measured | — | Gap - future training register (roadmap item) |
| 15.1 | Establish and Maintain an Inventory of Service Providers | yes | not measured | not measured | — | P9 vendor and licence register with renewal alerts |
| 17.1 | Designate Personnel to Manage Incident Handling | yes | not measured | not measured | — | P7 incident response roles and the tabletop exercise record |
| 17.2 | Establish and Maintain Contact Information for Reporting Security Incidents | yes | not measured | not measured | — | P7 incident contact list (internal vendors insurer and authorities) |
| 17.3 | Establish and Maintain an Enterprise Process for Reporting Incidents | yes | not measured | not measured | — | P7 incident reporting process plus the ransomware tabletop report |

## 5. Gaps and the 90-day roadmap

No scored gaps yet. When the assessment is run, every safeguard scoring below 3 is added to the risk register (`data/risk-register.csv`) and, if it cannot be fixed inside 90 days, to the roadmap in the State of IT talk. Control 14 (security awareness) is the expected largest gap because no awareness programme exists in the build kit.

## 6. Validation

Validation: clean — every safeguard id is unique, every status is inside the 0–3 scale, and no safeguard is scored 3 without an evidence source.

---

*Generated by `projects/p10-governance/scripts/cis_assessment.py`. The safeguard list is the public CIS Controls v8.1 IG1 list (56 safeguards); the official CIS document or the free CSAT tool is authoritative for wording.*
