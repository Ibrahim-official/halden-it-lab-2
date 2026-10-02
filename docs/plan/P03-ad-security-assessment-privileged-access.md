# P3: Active Directory Security Assessment and Privileged Access Hardening

> **Pitch:** Audited Active Directory with PingCastle, Purple Knight and BloodHound CE, found the misconfigurations attackers use (Kerberoastable service accounts, unconstrained delegation, shared local admin passwords, NTLMv1, stale admins), then remediated them with an admin tiering model, Windows LAPS, Protected Users, gMSAs and DC hardening. Risk score went from **X to Y** and attack paths to Domain Admin from **N to 0**.

**Anchor score:** 93 (merged with #5 tiering/LAPS and #10 password policy) · **Time:** about 1.5 weeks · **Depends on:** P1, P2

---

## 1. Business problem

Every workstation at Halden has the same local admin password. IT staff use one Domain Admin account for everything, including reading email. Service accounts have passwords set years ago that never expire. Once one laptop is phished, an attacker can reach the whole domain in hours.

**Market evidence:** credential abuse leads breach vectors, and ransomware is in 88% of SMB breaches (Verizon DBIR 2025). Ransomware operators almost always go for AD privilege escalation first, because domain admin rights let them push encryption to every machine. Windows LAPS is now built into Windows Server 2019+ (April 2023 update), 2022 and 2025, so there's no reason to skip it.

## 2. JD coverage

| Ad | Bullet proven |
|---|---|
| SysAdmin | System **hardening**; access controls on **least privilege** |
| SysAdmin | Identify and respond to **vulnerabilities and unauthorized access** |
| SysAdmin | **Perform regular security checks** and support remediation |
| Officer | Identify operational issues and **communicate them to management** (risk report) |

## 3. Success criteria

- [ ] PingCastle **global risk score reduced by ≥70%** (lower is better). Record the before/after in each of its four categories: Stale Objects, Privileged Accounts, Trusts, Anomalies.
- [ ] Purple Knight score improved; all **critical** indicators resolved or formally risk-accepted
- [ ] BloodHound CE: **0 attack paths** from "Domain Users" to "Domain Admins"
- [ ] **100% of workstations and member servers** have a unique, rotating local admin password (Windows LAPS)
- [ ] No human accounts in Domain Admins for daily use; Tier 0 accounts **cannot log on** to Tier 1/2 machines (verified)
- [ ] All service accounts converted to **gMSA** or have 25+ char passwords with justification
- [ ] Remediation tracker: every finding has an owner, action, status and evidence

## 4. Tools and cost

[PingCastle](https://www.pingcastle.com) (free basic edition for auditing your own AD) · [Purple Knight](https://www.semperis.com/purple-knight/) (free) · BloodHound Community Edition + SharpHound (free) · Windows LAPS (built in) · Microsoft's `New-KrbtgtKeys.ps1` script. **Cost: free.**

> ⚠️ Run BloodHound/SharpHound and any attack validation **only inside your isolated lab**. Say that explicitly in the README. It shows you understand authorization.

## 5. Step-by-step action plan

### Phase 0: Seed realistic misconfigurations (Day 1)
A clean lab gives a boring "before" score. Create the problems you'd really inherit (script it: `scripts/00-Seed-Weaknesses.ps1`, clearly labelled **LAB ONLY**):

| Weakness seeded | How |
|---|---|
| Kerberoastable account with weak password | `svc-sql` with SPN `MSSQLSvc/lnx01:1433`, password `Summer2019!`, PasswordNeverExpires |
| AS-REP roastable account | `Set-ADAccountControl old.user -DoesNotRequirePreAuth $true` |
| Unconstrained delegation on a server | `Set-ADComputer FS01 -TrustedForDelegation $true` |
| Too many / stale Domain Admins | Add 4 users incl. one disabled and one never logged in |
| Same local admin password everywhere | GPO or script sets `LocalAdmin` / `Halden123!` on WS01/WS02 |
| Weak domain policy | Min length 7, no lockout |
| Legacy protocols | LM compatibility level 1 (NTLMv1), SMB signing not required, Print Spooler running on DCs |
| AD Recycle Bin disabled | Default state |
| Old krbtgt password | Default state (note its age) |

### Phase 1: Assess, then write it up for management (Day 2–3)
```powershell
# PingCastle
.\PingCastle.exe --healthcheck --server ad.halden.internal     # → ad_hc_ad.halden.internal.html
# Purple Knight: run GUI, export PDF
# BloodHound CE (docker compose on LNX01), collect with SharpHound from a domain-joined box:
.\SharpHound.exe -c All --domain ad.halden.internal
```
- In BloodHound, run the "Shortest paths to Domain Admins" and "Kerberoastable users" queries and screenshot the graph. **This screenshot is the most memorable image in the portfolio.**
- Build `business/p3-findings-register.xlsx`: ID, finding, source tool, **risk (Likelihood × Impact, 1–5 each)**, affected objects, remediation, effort, owner, target date, status, evidence.
- Write `business/p3-exec-summary.md` (1 page, no jargon): "An attacker who phishes any one employee could take control of every computer in the company in under a day. Here are the 5 things we're fixing and when."

### Phase 2: Quick wins, low risk (Day 4)
1. **Enable AD Recycle Bin:** `Enable-ADOptionalFeature 'Recycle Bin Feature' -Scope ForestOrConfigurationSet -Target ad.halden.internal`
2. **Remove stale and unneeded Domain Admins.** Target membership: *only* the Tier 0 admin accounts + the built-in Administrator (which gets a long random password and is stored offline).
3. **Clear `DoesNotRequirePreAuth`** and remove unconstrained delegation (switch to constrained/RBCD if genuinely needed).
4. **Stop and disable the Print Spooler on DCs** (PrintNightmare class of risk) via a GPO linked to the Domain Controllers OU.
5. **Fine-Grained Password Policies (FGPP):**
   ```powershell
   New-ADFineGrainedPasswordPolicy -Name "FGPP-Admins" -Precedence 10 -MinPasswordLength 20 `
     -LockoutThreshold 5 -LockoutDuration 00:30:00 -ComplexityEnabled $true -MaxPasswordAge 180.00:00:00
   Add-ADFineGrainedPasswordPolicySubject "FGPP-Admins" -Subjects "G_Tier0_Admins","G_Tier1_Admins"
   ```
   Raise the default domain policy to 14+ characters with lockout 10 / 15 min (consistent with P1), following NIST 800-63B thinking: length over forced complexity, and no periodic resets for users unless there's evidence of compromise. Document your reasoning.

### Phase 3: Windows LAPS (Day 5)
```powershell
Update-LapsADSchema                                           # once, as Schema Admin
Set-LapsADComputerSelfPermission -Identity "OU=Workstations,OU=Computers,OU=Halden,DC=ad,DC=halden,DC=internal"
Set-LapsADComputerSelfPermission -Identity "OU=Servers,OU=Halden,DC=ad,DC=halden,DC=internal"
Set-LapsADReadPasswordPermission -Identity "OU=Workstations,..." -AllowedPrincipals "HALDEN\G_Tier2_Helpdesk"
Set-LapsADReadPasswordPermission -Identity "OU=Servers,..."      -AllowedPrincipals "HALDEN\G_Tier1_ServerAdmins"
```
GPO `WKS - LAPS - v1` (Computer Config → Admin Templates → System → LAPS):
`Configure password backup directory = Active Directory` · `Password complexity = large+small+numbers+specials` · `Length = 20` · `Age = 30 days` · **`Enable password encryption = Enabled`** (authorized decryptors = the helpdesk group) · `Post-authentication actions = reset password and log off after 8 hours`.
Also configure **DSRM password backup** for DCs (supported by Windows LAPS; mention it in interviews).
- **Verify:** `Get-LapsADPassword -Identity WS01 -AsPlainText` as the helpdesk account works; as a normal user it's denied. Event ID **10018** confirms a successful backup.

### Phase 4: Admin tiering model (Day 6–8)
Implement a practical, SMB-sized version of Microsoft's tier model (now part of the Enterprise Access Model):

| Tier | Controls | Admin accounts | Can log on to |
|---|---|---|---|
| **Tier 0** | DCs, AD, Entra Connect/Cloud Sync, PKI, backup of DCs | `adm-t0-*` | DCs and PAW only |
| **Tier 1** | Member servers, applications | `adm-t1-*` | Servers only |
| **Tier 2** | Workstations, users, helpdesk | `adm-t2-*` | Workstations only |

1. Create the `_Admin` OU structure: `Tier0\Accounts`, `Tier0\Groups`, `Tier1\...`, `Tier2\...`, `PAW\Devices`.
2. Each IT person gets **a separate daily-use account (no admin rights) plus tiered admin accounts.** No email or browsing with admin accounts.
3. **Logon restrictions via GPO** (User Rights Assignment):
   - On workstations (`WKS - Tier Restrictions`): *Deny log on locally / through RDP / as batch / as service* → `G_Tier0_Admins`, `G_Tier1_Admins`
   - On servers (`SRV - Tier Restrictions`): Deny → `G_Tier0_Admins`, `G_Tier2_Admins`
   - On DCs: Allow logon only for `G_Tier0_Admins` (+ built-in)
4. Add Tier 0 humans to **Protected Users** (no NTLM, no delegation, no cached creds, AES Kerberos only, 4-hour TGT). **Test first**: create a test account, confirm it still works, then add the real ones. Document which accounts must never go in (service accounts, computer accounts).
5. Set **"Account is sensitive and cannot be delegated"** on all admin accounts.
6. **Privileged Access Workstation (PAW), lab version:** designate WS02 as the Tier 0 PAW. No internet via firewall rule (added in P6), only Tier 0 logons allowed.
7. **Delegation instead of Domain Admin:** helpdesk (`G_Tier2_Helpdesk`) gets delegated *reset password + unlock* on user OUs only. Test it: the helpdesk account can reset a Sales user but **cannot** reset a Tier 0 admin.

### Phase 5: Service accounts and Kerberos hygiene (Day 9)
```powershell
Add-KdsRootKey -EffectiveTime ((Get-Date).AddHours(-10))   # lab only; production waits 10h for replication
New-ADServiceAccount -Name gmsa-sql -DNSHostName gmsa-sql.ad.halden.internal `
  -PrincipalsAllowedToRetrieveManagedPassword "G_SQL_Servers" -KerberosEncryptionType AES256
# On the server: Install-ADServiceAccount gmsa-sql ; Test-ADServiceAccount gmsa-sql
```
- Move the SPN from `svc-sql` to `gmsa-sql` (240-char auto-rotating password makes Kerberoasting pointless), then disable `svc-sql`.
- Restrict Kerberos encryption types to **AES only** (disable RC4) via GPO `Network security: Configure encryption types allowed for Kerberos`. First audit event 4769 for RC4 ticket requests (encryption type `0x17`) so you know what would break.
- **Reset krbtgt twice** (waiting for replication in between) using Microsoft's `New-KrbtgtKeys.ps1` in simulation mode first. Document it as a scheduled task done every 180 days and after any suspected compromise.

### Phase 6: Legacy protocol hardening (Day 10)
Do these through GPO. **Audit first, then enforce.** That's change control in practice.
| Setting | Target |
|---|---|
| LAN Manager authentication level | *Send NTLMv2 response only. Refuse LM & NTLM* (level 5) |
| NTLM auditing | `Network security: Restrict NTLM: Audit incoming NTLM traffic` = enable for all accounts, then review event 8004 on DCs |
| SMB signing | `Microsoft network server/client: Digitally sign communications (always)` = Enabled (default in Win11 24H2 / Server 2025; verify rather than assume) |
| LDAP signing + channel binding | DCs: `Domain controller: LDAP server signing requirements = Require signing`; `LDAP server channel binding token requirements = Always` |
| SMBv1 | Removed: `Get-WindowsOptionalFeature -Online -FeatureName SMB1Protocol` = Disabled |
| LLMNR / NetBIOS-NS | LLMNR off via GPO; NetBIOS over TCP/IP off via DHCP option or script |

### Phase 7: Re-assess and report (Day 11)
- Re-run PingCastle, Purple Knight and BloodHound. Build a **before/after table** by category, plus the "attack paths to DA" graph before (full of paths) and after (empty).
- Anything left open goes into a **risk acceptance** entry with a business owner and review date. That's how real organizations handle residual risk.
- Schedule `PingCastle --healthcheck` monthly (Task Scheduler), with results feeding P10's monthly report.

## 6. Business layer (IT Support Officer)

| Artifact | Purpose |
|---|---|
| `business/p3-exec-summary.md` | 1-page plain-English risk summary for management |
| `business/p3-findings-register.xlsx` | Risk-rated register with owners and dates (reused in P10) |
| `business/p3-admin-access-standard.md` | Policy: tiering, separate admin accounts, LAPS usage, who can read LAPS passwords, break-glass process |
| `business/p3-before-after.pptx` (5 slides) | Presentation to "management": problem, attack-path picture, what was fixed, score change, remaining risks and asks |

## 7. Evidence to capture

PingCastle before/after HTML (scores) · BloodHound attack-path graph before/after · LAPS password visible to helpdesk only, denied to user · Event 10018 · denied RDP when a Tier 0 account tries a workstation · Protected Users membership · gMSA `Test-ADServiceAccount` = True · NTLM audit events · findings register.

## 8. Common pitfalls

- Enforcing NTLM/LDAP/Kerberos changes **without an audit phase**, which breaks old apps. Always audit → analyse → enforce.
- Putting service or computer accounts into Protected Users.
- Resetting krbtgt twice in quick succession, which invalidates all tickets and causes an outage. Wait at least the max ticket lifetime (default 10h) plus replication.
- Tiering on paper only. **Test the deny-logon rules.**
- Leaving the seed script in a state where it can run on anything but the lab. Add a domain-name guard.

## 9. Resume bullets (templates)

- Performed an **Active Directory security assessment** (PingCastle, Purple Knight, BloodHound CE), producing a risk-rated register of **N findings**; remediation cut the PingCastle risk score from **X to Y (−Z%)** and removed **all attack paths** from standard users to Domain Admins.
- Implemented a **3-tier privileged access model** with separate admin accounts, GPO logon restrictions, Protected Users and delegated helpdesk rights, removing all daily-use accounts from Domain Admins.
- Deployed **Windows LAPS** with encrypted AD backup to 100% of endpoints, and replaced legacy service accounts with **gMSAs**, removing Kerberoasting exposure.

## 10. Interview talking points

- **"What would you check first in an AD you've inherited?"** Who's in the privileged groups, LAPS, service accounts with SPNs, delegation, krbtgt age, legacy protocols. Then run PingCastle for a baseline.
- **"Explain Kerberoasting to a manager, then to an engineer."** Manager: "anyone on the network can take a copy of some passwords and crack them offline." Engineer: TGS encrypted with the service account's hash, RC4 plus a weak password; the fix is gMSA plus AES only.
- **"How do you roll out a breaking security change?"** Audit mode, analyse the logs, communicate, pilot, enforce, and have a rollback plan through a change request (links to P10).

## 11. AI-ready build prompt

```text
Act as a senior Active Directory security engineer mentoring me through a homelab capstone.
Project: P3 AD Security Assessment & Privileged Access Hardening for fictional "Halden Distribution Ltd".
Existing: ad.halden.internal (Server 2025, DC01/DC02), FS01, WS01/WS02 (Win 11), LNX01 (Ubuntu), P1 OU design,
P2 JML automation. Everything is an isolated lab that I own.

Walk me through, one phase at a time:
0. A LAB-ONLY seed script (with a domain-name guard) creating realistic weaknesses: kerberoastable svc account,
   AS-REP roastable user, unconstrained delegation, excess/stale Domain Admins, shared local admin password,
   weak password policy, NTLMv1/SMB signing off/Spooler on DCs.
1. Assessment with PingCastle, Purple Knight and BloodHound CE (docker) — what each finding means, and a
   findings-register template with Likelihood x Impact scoring + a 1-page executive summary.
2. Quick wins (Recycle Bin, DA cleanup, delegation, Spooler, FGPP).
3. Windows LAPS with encryption, read-permission delegation, DSRM backup, verification (Event 10018).
4. 3-tier admin model: OU structure, GPO deny-logon rights, Protected Users (test-first), PAW, helpdesk delegation.
5. gMSA migration, AES-only Kerberos (audit 4769 first), safe double krbtgt reset.
6. NTLM/LDAP/SMB/LLMNR hardening using audit -> analyse -> enforce.
7. Re-assessment, before/after table, risk acceptance template, monthly scheduled health check.
For each phase: commands, expected output, verification test, screenshot list, and rollback steps.
End with the README, 5-slide management deck outline, and resume bullets using my real numbers. Start with Phase 0.
```
