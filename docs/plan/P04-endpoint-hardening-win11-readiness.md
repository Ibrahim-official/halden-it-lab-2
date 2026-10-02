# P4: Endpoint Hardening Baseline and Windows 11 Readiness Program

> **Pitch:** Built a measurable Windows endpoint security baseline (Microsoft Security Baseline + CIS Level 1 via GPO, Defender Antivirus with Attack Surface Reduction rules, BitLocker, firewall, removal of local admin rights), with an automated compliance report. Also produced a Windows 10 end-of-support readiness assessment with a costed replace/upgrade/ESU recommendation for management.

**Anchor score:** 87 (merged with #12 Win11 readiness, #13 BitLocker, #14 ASR) · **Time:** about 1.5 weeks · **Depends on:** P1 (GPO structure), P3 (LAPS/tiering)

---

## 1. Business problem

Halden's PCs were set up by whoever unboxed them. Users are local admins, BitLocker is off (a lost sales laptop means a data breach), Defender is on with default settings only, and about 30% of PCs still run **Windows 10**, which lost support on **14 Oct 2025**.

**Market evidence:** about 21% of SMB Windows devices were still on Windows 10 in mid-2026 (Lansweeper via Computer Weekly). Microsoft's commercial Extended Security Updates run for at most 3 years (to Oct 2028) and must be paid for each year. Ransomware, the main SMB threat, usually runs on endpoints and relies on script abuse, Office macros and credential theft. ASR rules and baseline hardening target exactly those.

## 2. JD coverage

| Ad | Bullet proven |
|---|---|
| SysAdmin | Maintain **endpoint protection**, updates, **system hardening** |
| SysAdmin | Perform regular security checks |
| SysAdmin | Follow IT security policies and change control |
| Officer | Prepare reports and business updates; identify operational issues and communicate to management; support business projects (hardware refresh) |

## 3. Success criteria

- [ ] Baseline compliance (HardeningKitty or CIS-CAT Lite score) raised from **X% to ≥90%** on Win 11 clients
- [ ] **16+ Defender ASR rules** audited for 7 days, then set to Block (documented exceptions only)
- [ ] **BitLocker (XTS-AES 256, TPM)** on 100% of clients; recovery keys escrowed to AD and retrieval tested
- [ ] **0 standard users with local admin rights** (verified by script)
- [ ] Automated daily **compliance report** (HTML + CSV) covering all controls
- [ ] Windows 11 readiness report with fleet counts (ready / upgrade / replace) and a **costed 3-option recommendation**

## 4. Tools and cost

[Microsoft Security Compliance Toolkit](https://www.microsoft.com/en-us/download/details.aspx?id=55319) (baselines, Policy Analyzer, LGPO) · [CIS-CAT Lite](https://www.cisecurity.org/cybersecurity-tools/cis-cat-pro/cis-cat-faq) (free) or [HardeningKitty](https://github.com/scipag/HardeningKitty) (open source) · Microsoft Defender Antivirus (built in) · PowerShell · Excel/Power BI Desktop (free). **Cost: free.**

## 5. Step-by-step action plan

### Phase 0: Baseline measurement, the "before" (Day 1)
1. On WS01 (default install, user made a local admin to simulate the inherited state):
   ```powershell
   Import-Module .\HardeningKitty.psm1
   Invoke-HardeningKitty -Mode Audit -FileFindingList .\lists\finding_list_cis_microsoft_windows_11_enterprise_23h2_machine.csv `
     -Log -Report -ReportFile .\evidence\wks01-before.csv
   ```
   (Use the latest list version available. CIS-CAT Lite gives a similar % score.)
2. Record: score %, BitLocker status, local admin members, Defender config (`Get-MpPreference`), ASR state.

### Phase 1: Import Microsoft Security Baselines via GPO (Day 2–3)
1. Download the **Windows 11 (current version) + Windows Server 2025 security baselines** from the Security Compliance Toolkit.
2. Import into new GPOs (don't edit the originals, so you can compare and upgrade later):
   ```powershell
   Import-GPO -BackupGpoName "MSFT Windows 11 24H2 - Computer" -Path .\Baseline\GPOs -TargetName "WKS - MSFT Baseline Computer - v1" -CreateIfNeeded
   ```
3. Use **Policy Analyzer** to compare the baseline with your existing GPOs (P1–P3) and **document conflicts** and which one wins. Export the comparison to Excel for evidence.
4. Add a small **`WKS - Halden Overrides - v1`** GPO with higher link precedence for justified deviations (e.g. allow a specific legacy app). Every deviation needs a line in `docs/baseline-exceptions.md` with its reason, risk and owner. **This is change control plus a policy exceptions register.**
5. Deploy to a **pilot OU** (`Workstations\Pilot` with WS02) for 3 days, then to all. Document the rollout rings.

### Phase 2: Defender Antivirus and ASR rules (Day 4–5)
GPO `WKS - Defender - v1` (or PowerShell for the lab):
```powershell
Set-MpPreference -PUAProtection Enabled -CloudBlockLevel High -CloudExtendedTimeout 50 `
  -MAPSReporting Advanced -SubmitSamplesConsent SendSafeSamples -EnableNetworkProtection Enabled
# ASR rules: start in AUDIT (2), move to BLOCK (1) after review
$asr = @{
 'be9ba2d9-53ea-4cdc-84e5-9b1eeee46550'='Block executable content from email client and webmail'
 'd4f940ab-401b-4efc-aadc-ad5f3c50688a'='Block Office apps from creating child processes'
 '3b576869-a4ec-4529-8536-b80a7769e899'='Block Office apps from creating executable content'
 '75668c1f-73b5-4cf0-bb93-3ecf5cb7cc84'='Block Office apps from injecting code into other processes'
 'd3e037e1-3eb8-44c8-a917-57927947596d'='Block JavaScript/VBScript from launching downloaded executable content'
 '5beb7efe-fd9a-4556-801d-275e5ffc04cc'='Block execution of potentially obfuscated scripts'
 '92e97fa1-2edf-4476-bdd6-9dd0b4dddc7b'='Block Win32 API calls from Office macros'
 '9e6c4e1f-7d60-472f-ba1a-a39ef669e4b2'='Block credential stealing from LSASS'
 'd1e49aac-8f56-4280-b9ba-993a6d77406c'='Block process creations from PSExec and WMI commands'
 'b2b3f03d-6a65-4f7b-a9c7-1c7ef74a9ba4'='Block untrusted and unsigned processes that run from USB'
 'c1db55ab-c21a-4637-bb3f-a12568109d35'='Use advanced protection against ransomware'
 'e6db77e5-3df2-4cf1-b95a-636979351e5b'='Block persistence through WMI event subscription'
 '56a863a9-875e-4185-98a7-b882c64b5ce5'='Block abuse of exploited vulnerable signed drivers'
 '26190899-1602-49e8-8b27-eb1d0a1ce869'='Block Office communication app from creating child processes'
 '7674ba52-37eb-4a4f-a9a1-f0f9a1619a2c'='Block Adobe Reader from creating child processes'
 '01443614-cd74-433a-b99e-2ecdc07bfc25'='Block executable files unless they meet prevalence, age, or trusted list criteria'
}
foreach ($id in $asr.Keys) { Add-MpPreference -AttackSurfaceReductionRules_Ids $id -AttackSurfaceReductionRules_Actions AuditMode }
```
- **Check every GUID against Microsoft Learn's "ASR rules reference"** before deploying. Note that the PSExec/WMI rule can conflict with management tooling (e.g. ConfigMgr), so decide on it deliberately.
- Enable **Controlled Folder Access** in audit mode for the Documents/Desktop folders.
- Review audit events (**Event ID 1122** = ASR audited, **1121** = blocked, in `Microsoft-Windows-Windows Defender/Operational`) for 7 days. Test triggers: a macro-enabled test document from Microsoft's ASR test pages and the **EICAR** test file.
- Switch to Block and document exclusions (path/process, with justification).
- **Tamper Protection:** on in Windows Security (centrally managed only via Intune/MDE; note this limitation in the README).

### Phase 3: BitLocker with AD key escrow (Day 5)
GPO `WKS - BitLocker - v1`: store recovery info in AD DS (**required before enabling**), XTS-AES 256 for OS and fixed drives, TPM-only startup (optionally TPM+PIN for laptops, and explain the trade-off).
```powershell
Enable-BitLocker -MountPoint C: -EncryptionMethod XtsAes256 -TpmProtector -UsedSpaceOnly
Add-BitLockerKeyProtector -MountPoint C: -RecoveryPasswordProtector
$kp = (Get-BitLockerVolume C:).KeyProtector | ? KeyProtectorType -eq RecoveryPassword
Backup-BitLockerKeyProtector -MountPoint C: -KeyProtectorId $kp.KeyProtectorId
# Verify escrow from a DC:
Get-ADObject -Filter 'objectClass -eq "msFVE-RecoveryInformation"' -SearchBase (Get-ADComputer WS01).DistinguishedName -Properties msFVE-RecoveryPassword
```
- In Proxmox/Hyper-V, add a **vTPM** to the Win11 VMs (needed for Win11 anyway).
- **Test recovery:** force recovery mode (`manage-bde -forcerecovery C:`), reboot, retrieve the key as a helpdesk user, unlock. Write the **"BitLocker recovery" helpdesk runbook** with an identity-verification step. Social engineering of recovery keys is a real attack.

### Phase 4: Remove local admin rights and extra hardening (Day 6)
1. GPO **Restricted Groups / Group Policy Preferences → Local Users and Groups**: local Administrators = `Administrator` (LAPS-managed) + `G_Tier2_Admins` only. **Remove "Domain Users"** and everyone else.
2. For users who "need admin for one app", write a short **exception process** (ticket, manager approval, time-limited) and mention **Endpoint Privilege Management** as the future-state tool.
3. Windows Defender Firewall GPO: on for all profiles, inbound default block, allow RDP/WinRM **only from the management subnet** (defined in P6).
4. **Credential Guard** (on by default on eligible Win11 Enterprise 22H2+; verify with `msinfo32` → Virtualization-based security) and **LSA protection** (`RunAsPPL`).
5. **PowerShell logging:** Script Block Logging + Module Logging on (P7 ingests these), plus Constrained Language Mode notes as a stretch goal.
6. Stretch: **AppLocker in audit mode** with default rules plus a publisher rule for the line-of-business app.

### Phase 5: Automated compliance report (Day 7–8)
`scripts/Get-EndpointCompliance.ps1` runs daily from a management server using `Invoke-Command` against all computers in the Workstations OU:

| Check | Pass condition |
|---|---|
| OS build | ≥ current supported Win 11 release |
| BitLocker | OS volume `FullyEncrypted`, protection On, key in AD |
| Defender | RealTimeProtection On, signatures < 24h old, last quick scan < 7d |
| ASR | All approved rules = Block (1) |
| Firewall | All profiles enabled |
| Local admins | Only approved members |
| LAPS | Password last set < 31 days |
| Pending reboot | False |
| Last patch install | < 35 days (ties to P5) |

Output: `reports/endpoint-compliance-<date>.html` with a traffic-light table, overall % compliant, and a CSV for Power BI. The trend over time feeds the P10 monthly report.

### Phase 6: Windows 11 readiness assessment (Day 9–10)
1. `scripts/Get-Win11Readiness.ps1` collects: OS/version/build, **TPM 2.0 present and enabled**, **Secure Boot**, UEFI, CPU model (compare with Microsoft's supported CPU list), RAM ≥4 GB, disk ≥64 GB, device age (from BIOS date), model.
2. The lab only has a few VMs, so create **`data/synthetic-fleet.csv` (85 devices)**, **clearly labelled synthetic**, with a realistic mix: e.g. 60 Win11-ready, 15 Win10 on capable hardware, 10 Win10 on incapable hardware (7th-gen Intel or older / no TPM 2.0).
3. Analyse in Excel/Power BI: counts by department and by status, and which departments have critical devices (e.g. warehouse scanners, finance PCs).
4. **Costed options for management** (use current vendor prices; verify ESU pricing at the time of writing):
   | Option | Description | Cost | Risk |
   |---|---|---|---|
   | A | Upgrade 15 capable devices in-place now; replace 10 incapable devices this quarter | Labour + 10 × device cost | Lowest |
   | B | Upgrade the capable devices; buy ESU year 1 for the incapable devices, replace next FY | Labour + ESU (price doubles each year) + devices later | Medium: ESU is a bridge, not a plan |
   | C | Do nothing | Nothing now | **High**: unpatched OS, insurance/compliance exposure |
5. Upgrade one Win10 VM to Win11 **in the lab** with a documented checklist (backup → compatibility check → app test → in-place upgrade → post-checks → rollback window).

## 6. Business layer (IT Support Officer)

| Artifact | Purpose |
|---|---|
| `business/p4-win11-readiness-report.pdf` (3–4 pages) | Exec summary, fleet status chart, 3 options with costs and risks, recommendation, timeline |
| `business/p4-endpoint-standard.md` | Endpoint security standard (what every Halden PC must have) |
| `business/p4-baseline-exceptions.md` | Exceptions register |
| `business/p4-user-comms.md` | "Why you no longer have admin rights, and how to request software" + the software request process |

## 7. Evidence to capture

HardeningKitty/CIS-CAT before/after score · Policy Analyzer diff · ASR events 1122→1121 · EICAR blocked · BitLocker key in AD + recovery test · local admins before/after · compliance HTML report · readiness charts · Win10→11 upgrade checklist.

## 8. Common pitfalls

- Enabling BitLocker **before** the GPO requiring AD escrow is in place leaves keys in nobody's hands.
- Going straight to ASR Block breaks Finance's macros on Monday morning. **Always audit first.**
- Editing Microsoft's baseline GPOs directly makes the next baseline upgrade painful. Use an overrides GPO.
- Assuming SMB signing, Credential Guard and similar are on because "Win11 does it by default". **Verify and report.**

## 9. Resume bullets (templates)

- Hardened Windows 11 endpoints with **Microsoft Security Baselines, 16 Defender ASR rules (audit → block), BitLocker with AD key escrow and LAPS**, raising CIS benchmark compliance from **X% to Y%** and removing local admin rights from all standard users.
- Built an automated **PowerShell endpoint compliance report** (9 controls, daily, HTML/CSV) that gave management a single "% compliant" KPI.
- Produced a **Windows 10 end-of-support readiness assessment** for an 85-device fleet with a costed upgrade/replace/ESU recommendation and an in-place upgrade runbook.

## 10. Interview talking points

- **"A user says they need admin rights."** Understand the actual need, then decide between a packaged install, a time-limited elevation or an exception, with approval and logging. Never permanent by default.
- **"How do you deploy ASR without breaking the business?"** Audit mode, event review, targeted exclusions, pilot ring, block, and monitoring.
- **"Windows 10 is out of support. What do you tell the CFO?"** Risk, three options, cost of each, recommendation, timeline. ESU is a bridge, not a strategy.

## 11. AI-ready build prompt

```text
Act as a senior endpoint security engineer and IT manager mentoring me on a homelab capstone.
Project: P4 Endpoint Hardening Baseline & Windows 11 Readiness, fictional "Halden Distribution Ltd" (85 devices).
Existing: ad.halden.internal with P1 GPO structure (WKS OUs incl. a Pilot OU), P3 LAPS and tiering.
Lab clients: WS01, WS02 (Win 11 Enterprise eval with vTPM) plus one Win10 VM to upgrade.

Guide me phase by phase:
0. Baseline measurement with HardeningKitty (or CIS-CAT Lite): exact commands and how to read the score.
1. Import the current Microsoft Security Baseline via GPO, Policy Analyzer conflict review, an overrides GPO and an
   exceptions register, and pilot → broad rollout rings.
2. Defender AV hardening + ASR rules (verify each GUID against Microsoft Learn), audit → block with event review
   (1121/1122), Controlled Folder Access, safe test triggers (EICAR, Microsoft ASR test files).
3. BitLocker XTS-AES 256 with AD escrow, recovery test, and a helpdesk recovery runbook with identity verification.
4. Local admin removal via GPO, firewall GPO, Credential Guard/LSA protection, PowerShell logging.
5. Get-EndpointCompliance.ps1 (9 checks, HTML traffic-light report + CSV) scheduled daily.
6. Get-Win11Readiness.ps1 + a synthetic 85-device fleet CSV, Excel/Power BI analysis, and a 3-option
   costed recommendation report (remind me to check current ESU and hardware prices).
For each phase: commands, expected output, verification, screenshots, rollback. Finish with README, management
report outline and resume bullets using my numbers. Start with Phase 0.
```
