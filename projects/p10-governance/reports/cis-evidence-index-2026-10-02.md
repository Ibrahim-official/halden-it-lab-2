# Halden Distribution Ltd. — CIS IG1 compliance evidence index

**As of:** 2026-10-02  **Safeguards indexed:** 56  **Expected artifacts present today:** 16 of 56

> This indexes the **repository**, not the lab. An artifact is *present* when the file named in `configs/cis-ig1-evidence-map.csv` exists in this repository today. Because the lab has not been executed, most artifacts are *expected - not present*: that is the honest state of an unexecuted build kit, and it is why no safeguard is scored yet.

## Where the evidence will come from

| Source project | Safeguards it is expected to evidence | Artifacts present today |
|---|---|---|
| P1 | 7 | 5 |
| P10 | 7 | 7 |
| P2 | 5 | 1 |
| P3 | 4 | 3 |
| P4 | 8 | 1 |
| P5 | 4 | 1 |
| P6 | 5 | 1 |
| P7 | 5 | 0 |
| P8 | 4 | 1 |
| P9 | 7 | 1 |
| Gap - 90-day roadmap item | 8 | 0 |

## Safeguard by safeguard

| Safeguard | Title | Expected evidence | Artifact | State |
|---|---|---|---|---|
| 1.1 | Establish and Maintain Detailed Enterprise Asset Inventory | GLPI asset inventory (P9) reconciled with a network scan and the DHCP/AD computer objects | `projects/p09-service-desk-cmdb/evidence/public/p09-ph2-reconciliation-result.csv` | expected - not present |
| 1.2 | Address Unauthorized Assets | GLPI reconciliation run showing 0 unknown devices and the process note for quarantine | `projects/p09-service-desk-cmdb/evidence/public/p09-ph2-reconciliation-result.csv` | expected - not present |
| 2.1 | Establish and Maintain a Software Inventory | GLPI software inventory export with publisher and version | `projects/p09-service-desk-cmdb/evidence/public/p09-ph2-software-inventory-result.csv` | expected - not present |
| 2.2 | Ensure Authorized Software is Currently Supported | Windows 11 readiness report listing unsupported Windows 10 devices and the ESU/exception decision | `projects/p04-endpoint-hardening/evidence/public/p04-ph1-win11-readiness-report.pdf` | expected - not present |
| 2.3 | Address Unauthorized Software | GLPI software inventory with the unauthorised-software review column | `projects/p09-service-desk-cmdb/evidence/public/p09-ph2-software-inventory-result.csv` | expected - not present |
| 3.1 | Establish and Maintain a Data Management Process | Data Protection section of the P10 policy pack (owner review date and exceptions process) | `projects/p10-governance/business/p10-policy-pack.md` | present |
| 3.2 | Establish and Maintain a Data Inventory | GLPI asset/data inventory plus the permissions matrix showing Finance and HR data owners | `projects/p09-service-desk-cmdb/evidence/public/p09-ph2-asset-inventory-result.csv` | expected - not present |
| 3.3 | Configure Data Access Control Lists | AGDLP permission matrix and the PowerShell ACL audit reporting 0 violations | `projects/p01-core-infrastructure/business/p01-permission-matrix.csv` | present |
| 3.4 | Enforce Data Retention | Retention schedule in the P10 policy pack (Finance and HR retention periods) | `projects/p10-governance/business/p10-policy-pack.md` | present |
| 3.5 | Securely Dispose of Data | Disposal and leaver-data-handling section of the P10 policy pack | `projects/p10-governance/business/p10-policy-pack.md` | present |
| 3.6 | Encrypt Data on End-User Devices | BitLocker escrow proof - recovery key stored in AD and a successful recovery test | `projects/p04-endpoint-hardening/evidence/public/p04-ph3-bitlocker-escrow-result.png` | expected - not present |
| 4.1 | Establish and Maintain a Secure Configuration Process | P1 GPO baseline plus the as-built document describing the build standard | `projects/p01-core-infrastructure/docs/as-built.md` | present |
| 4.2 | Establish and Maintain a Secure Configuration Process for Network Infrastructure | P6 firewall rule matrix and the network standard in the P10 policy pack | `projects/p10-governance/business/p10-policy-pack.md` | present |
| 4.3 | Configure Automatic Session Locking on Enterprise Assets | Desktop standards GPO (secure screen saver 600s) evidenced by gpresult on WS01 | `projects/p01-core-infrastructure/docs/as-built.md` | present |
| 4.4 | Implement and Manage a Firewall on Servers | Segmentation test results showing server ports filtered by the firewall | `projects/p06-network-segmentation/evidence/public/p06-ph3-segmentation-results.csv` | expected - not present |
| 4.5 | Implement and Manage a Firewall on End-User Devices | Host firewall baseline in the P4 security baseline and the compliance report | `projects/p04-endpoint-hardening/evidence/public/p04-ph2-asr-block-result.png` | expected - not present |
| 4.6 | Securely Manage Enterprise Assets and Software | P9 config-as-code (GPO and firewall configs versioned in Git) with the container compose file | `projects/p09-service-desk-cmdb/configs/docker-compose.yml` | present |
| 4.7 | Manage Default Accounts on Enterprise Assets and Software | Windows LAPS GPO settings and the disabled built-in administrator account | `projects/p03-ad-security/configs/p03-laps-gpo-settings.conf` | present |
| 5.1 | Establish and Maintain an Inventory of Accounts | P2 account inventory and the quarterly access review report | `projects/p02-identity-lifecycle/evidence/public/p02-ph1-account-inventory-result.csv` | expected - not present |
| 5.2 | Use Unique Passwords | Domain password and lockout GPO (14 character minimum) from the P1 baseline | `projects/p01-core-infrastructure/docs/as-built.md` | present |
| 5.3 | Disable Dormant Accounts | P2 dormant-account hygiene report (0 stale enabled accounts targeted) | `projects/p02-identity-lifecycle/evidence/public/p02-ph4-dormant-accounts-result.csv` | expected - not present |
| 5.4 | Restrict Administrator Privileges to Dedicated Administrator Accounts | P3 privileged access tiering model (Tier 0/1/2) with dedicated adm- accounts | `projects/p03-ad-security/configs/p03-tiering-model.csv` | present |
| 6.1 | Establish an Access Granting Process | P1 runbook "Add a new Halden user" plus the P2 joiner automation | `projects/p01-core-infrastructure/docs/runbooks/add-a-new-user.md` | present |
| 6.2 | Establish an Access Revoking Process | P2 leaver run: account disabled moved to Disabled OU and sessions revoked | `projects/p02-identity-lifecycle/evidence/public/p02-ph3-leaver-revocation-result.png` | expected - not present |
| 6.3 | Require MFA for Externally-Exposed Applications | P2 MFA coverage report (Conditional Access enforced for all users) | `projects/p02-identity-lifecycle/evidence/public/p02-ph5-mfa-coverage-result.png` | expected - not present |
| 6.4 | Require MFA for Remote Network Access | P6 VPN MFA prompt and the RADIUS/NPS decision note | `projects/p06-network-segmentation/evidence/public/p06-ph5-vpn-mfa-result.png` | expected - not present |
| 6.5 | Require MFA for Administrative Access | P3 privileged access standard and the MFA-enforced admin sign-in proof | `projects/p03-ad-security/evidence/public/p03-ph5-laps-access-denied-result.png` | expected - not present |
| 7.1 | Establish and Maintain a Vulnerability Management Process | Vulnerability Management section of the P10 policy pack | `projects/p10-governance/business/p10-policy-pack.md` | present |
| 7.2 | Establish and Maintain a Remediation Process | P3 remediation priority rules and the P5 tiering decision record | `projects/p03-ad-security/configs/p03-remediation-priority-rules.json` | present |
| 7.3 | Perform Automated Operating System Patch Management | P5 WSUS ring patch compliance report (target 95% within 14 days) | `projects/p05-vuln-management/evidence/public/p05-ph4-patch-compliance-result.csv` | expected - not present |
| 7.4 | Perform Automated Application Patch Management | P5 application patch coverage from the same ring compliance report | `projects/p05-vuln-management/evidence/public/p05-ph4-patch-compliance-result.csv` | expected - not present |
| 8.1 | Establish and Maintain an Audit Log Management Process | Logging and Monitoring section of the P10 policy pack | `projects/p10-governance/business/p10-policy-pack.md` | present |
| 8.2 | Collect Audit Logs | P7 Wazuh agents reporting and the enabled security audit policy | `projects/p07-siem-incident-response/evidence/public/p07-ph2-wazuh-agents-result.png` | expected - not present |
| 8.3 | Ensure Adequate Audit Log Storage | P7 Wazuh retention and index storage proof (90 days) | `projects/p07-siem-incident-response/evidence/public/p07-ph3-log-retention-result.png` | expected - not present |
| 9.1 | Ensure Use of Only Fully Supported Browsers and Email Clients | P4 supported-browser baseline in the compliance report | `projects/p04-endpoint-hardening/evidence/public/p04-ph1-browser-support-result.png` | expected - not present |
| 9.2 | Use DNS Filtering Services | P6 DNS filtering (AdGuard Home/Quad9) client configuration proof | `projects/p06-network-segmentation/evidence/public/p06-ph7-dns-filtering-result.png` | expected - not present |
| 10.1 | Deploy and Maintain Anti-Malware Software | P4 Microsoft Defender status across the fleet in the compliance report | `projects/p04-endpoint-hardening/evidence/public/p04-ph2-defender-status-result.png` | expected - not present |
| 10.2 | Configure Automatic Anti-Malware Signature Updates | Defender signature update policy and last-update proof | `projects/p04-endpoint-hardening/evidence/public/p04-ph2-defender-status-result.png` | expected - not present |
| 10.3 | Disable Autorun and Autoplay for Removable Media | P4 baseline policy disabling autorun and autoplay | `projects/p04-endpoint-hardening/evidence/public/p04-ph2-autorun-disabled-result.png` | expected - not present |
| 11.1 | Establish and Maintain a Data Recovery Process | P8 backup and DR design plus the Backup and Recovery section of the policy pack | `projects/p08-backup-dr/docs/diagrams/p08-architecture.svg` | present |
| 11.2 | Perform Automated Backups | P8 weekly automated restore-test history | `projects/p08-backup-dr/evidence/public/p08-ph3-restore-test-result.csv` | expected - not present |
| 11.3 | Protect Recovery Data | P8 repository encryption and immutability proof | `projects/p08-backup-dr/evidence/public/p08-ph4-immutability-result.png` | expected - not present |
| 11.4 | Establish and Maintain an Isolated Instance of Recovery Data | P8 immutability deletion-refused proof for the isolated offsite copy | `projects/p08-backup-dr/evidence/public/p08-ph4-immutability-result.png` | expected - not present |
| 12.1 | Ensure Network Infrastructure is Up-to-Date | P5 firmware patching record for FW01/FW02 and the support review | `projects/p05-vuln-management/evidence/public/p05-ph6-firmware-patch-result.csv` | expected - not present |
| 14.1 | Establish and Maintain a Security Awareness Program | Gap: no awareness programme exists yet - tracked in the P10 90-day roadmap | `projects/p10-governance/evidence/public/p10-ph5-awareness-training-register-result.csv` | expected - not present |
| 14.2 | Train Workforce Members to Recognize Social Engineering Attacks | Gap - future phishing simulation and training register (roadmap item) | `projects/p10-governance/evidence/public/p10-ph5-awareness-training-register-result.csv` | expected - not present |
| 14.3 | Train Workforce Members on Authentication Best Practices | Gap - future training register (roadmap item) | `projects/p10-governance/evidence/public/p10-ph5-awareness-training-register-result.csv` | expected - not present |
| 14.4 | Train Workforce on Data Handling Best Practices | Gap - future training register (roadmap item) | `projects/p10-governance/evidence/public/p10-ph5-awareness-training-register-result.csv` | expected - not present |
| 14.5 | Train Workforce Members on Causes of Unintentional Data Exposure | Gap - future training register (roadmap item) | `projects/p10-governance/evidence/public/p10-ph5-awareness-training-register-result.csv` | expected - not present |
| 14.6 | Train Workforce Members on Recognizing and Reporting Security Incidents | Gap - future training register (roadmap item) | `projects/p10-governance/evidence/public/p10-ph5-awareness-training-register-result.csv` | expected - not present |
| 14.7 | Train Workforce on How to Identify and Report if Their Enterprise Assets are Missing Security Updates | Gap - future training register (roadmap item) | `projects/p10-governance/evidence/public/p10-ph5-awareness-training-register-result.csv` | expected - not present |
| 14.8 | Train Workforce on the Dangers of Connecting to and Transmitting Enterprise Data Over Insecure Networks | Gap - future training register (roadmap item) | `projects/p10-governance/evidence/public/p10-ph5-awareness-training-register-result.csv` | expected - not present |
| 15.1 | Establish and Maintain an Inventory of Service Providers | P9 vendor and licence register with renewal alerts | `projects/p09-service-desk-cmdb/evidence/public/p09-ph6-vendor-register-result.csv` | expected - not present |
| 17.1 | Designate Personnel to Manage Incident Handling | P7 incident response roles and the tabletop exercise record | `projects/p07-siem-incident-response/evidence/public/p07-ph6-ir-roles-result.md` | expected - not present |
| 17.2 | Establish and Maintain Contact Information for Reporting Security Incidents | P7 incident contact list (internal vendors insurer and authorities) | `projects/p07-siem-incident-response/evidence/public/p07-ph6-ir-contact-list-result.md` | expected - not present |
| 17.3 | Establish and Maintain an Enterprise Process for Reporting Incidents | P7 incident reporting process plus the ransomware tabletop report | `projects/p07-siem-incident-response/evidence/public/p07-ph7-tabletop-report.pdf` | expected - not present |

## What this does not say

- It does not score any safeguard. A file existing is one input to a score, `0`–`3`, which a human writes after reading it.
- It does not cover the eight Control 14 safeguards, which depend on a security awareness programme that does not exist yet. They are recorded as roadmap items.

---

*Generated by `projects/p10-governance/scripts/evidence_index.py`.*
