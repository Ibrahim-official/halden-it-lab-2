# P2: Identity Lifecycle and Access Governance (JML Automation, MFA, Conditional Access, Access Reviews)

> **Pitch:** Replaced a manual, email-driven account process with an automated Joiner-Mover-Leaver pipeline driven by an HR export, synced identities to Microsoft Entra ID, enforced MFA through Conditional Access, and introduced quarterly access reviews signed off by department heads. Leaver access now goes from "whenever someone remembers" to under 15 minutes, with a full audit trail.

**Anchor score:** 94 · **Time:** about 2 weeks · **Depends on:** P1 (AD, OUs, AGDLP groups)

---

## 1. Business problem

At Halden, HR emails IT when someone joins, moves or leaves. Sometimes. New starters wait 2–3 days for access. People who change department keep their old access ("permission creep"). Leavers' accounts stay active for weeks. There's no MFA, and the Finance Director can't say who has access to payroll.

**Market evidence:** credential abuse is the top initial access vector (22% of breaches, Verizon DBIR 2025). MFA reduced account compromise risk by 99.22% in Microsoft's study. Offboarding gaps and orphaned accounts are among the most common findings in access audits.

## 2. JD coverage

| Ad | Bullet proven |
|---|---|
| SysAdmin | Manage user accounts, permissions, groups, **MFA**, access controls on **least privilege** |
| SysAdmin | Follow access-management standards; identify unauthorized access |
| Officer | Work with departments (HR, dept heads); process improvement; maintain accurate records |
| Officer | Coordinate and follow up on action items (review sign-offs) |

## 3. Success criteria

- [ ] **Joiner:** account + role groups + home drive + (cloud) licence created automatically, ready before day 1
- [ ] **Mover:** old-department groups removed and new ones added in the **same run** (no permission creep)
- [ ] **Leaver:** disabled, groups stripped (and recorded), sessions revoked, moved to `Disabled` OU within **≤15 min** of the HR file change
- [ ] Stale-account report: enabled accounts with no logon in 90+ days → **0** unexplained
- [ ] Hybrid identity: AD users synced to Entra ID; **MFA required for 100% of users** via Conditional Access; legacy auth blocked
- [ ] ScubaGear (CISA) tenant report, **before vs after** pass counts
- [ ] Quarterly access review pack produced and "signed" by each department head, with actions tracked to closure

## 4. Architecture / flow

```
 HR system export (CSV, nightly)          Request form (GLPI/Forms) for exceptions
            │                                         │
            ▼                                         ▼
  Invoke-HaldenJML.ps1  ── compares HR "source of truth" vs AD current state ──┐
     │         │           │                                                   │
  JOINER     MOVER       LEAVER                                                │
     │         │           │                                                   ▼
     ▼         ▼           ▼                                         logs/jml-audit.csv
  AD DS (P1 OUs, AGDLP) ──── Entra Cloud Sync ────► Microsoft Entra ID
                                                     ├─ Conditional Access (MFA, block legacy)
                                                     ├─ Break-glass accounts (excluded, monitored)
                                                     └─ ScubaGear / Maester assessment
  Quarterly: Export-AccessReview.ps1 → per-department Excel → head signs off → removals → closed actions
```

## 5. Tools and cost

PowerShell (ActiveDirectory module, Microsoft.Graph module), **Microsoft Entra Cloud Sync** (lightweight agent; Entra Connect Sync is also fine), a **Microsoft 365 Business Premium trial** (includes Entra ID P1 for Conditional Access), [ScubaGear](https://github.com/cisagov/ScubaGear), optional [Maester](https://maester.dev). **Cost: free within the 30-day trial.** Do all cloud phases inside that window.

> No trial available? Use an **Entra ID Free** tenant with **Security Defaults** (tenant-wide MFA) and document Conditional Access as the design you'd deploy with P1 licensing.

## 6. Step-by-step action plan

### Phase 0: Map the current process with the business (Day 1)
This is the IT Support Officer half, so do it first.
1. Draw the **as-is** JML process (swimlanes: HR → Line Manager → IT → Employee). Mark the waits, handoffs and failure points (e.g. "HR forgets to email IT").
2. Define the **role-based access model** in `business/p2-role-matrix.xlsx`: Title/Department → role groups → apps/shares. Get "sign-off" from each department head (role-play it, and write their names in).
3. Agree on **SLAs** with HR: Joiner ready by Day −1, Mover same day, **Leaver within 1 hour** (15 min automated target), with an emergency "immediate" leaver path.
4. Draw the **to-be** process. This is your process-improvement artifact.

### Phase 1: Source-of-truth file and the JML engine (Day 2–5)
1. `data/hr-export.csv` columns: `EmployeeID, First, Last, Department, Title, ManagerID, Status (Active/Leaver), StartDate, EndDate`.
   **Key on `EmployeeID`, never on names.** Names change and collide.
2. `scripts/Invoke-HaldenJML.ps1` logic:
   ```powershell
   param([string]$HrFile = '.\data\hr-export.csv', [switch]$WhatIf)
   $hr    = Import-Csv $HrFile
   $ad    = Get-ADUser -Filter * -SearchBase 'OU=Users,OU=Halden,DC=ad,DC=halden,DC=internal' `
              -Properties EmployeeID,Department,Title,Manager,MemberOf,Enabled
   $roles = Import-Csv '.\data\role-matrix.csv'   # Department,Title -> Groups (semicolon list)

   foreach ($p in $hr) {
     $u = $ad | Where-Object EmployeeID -eq $p.EmployeeID
     if (-not $u -and $p.Status -eq 'Active' -and [datetime]$p.StartDate -le (Get-Date).AddDays(7)) { New-Joiner  $p }
     elseif ($u -and $p.Status -eq 'Leaver' -and [datetime]$p.EndDate -le (Get-Date))                { Invoke-Leaver $u $p }
     elseif ($u -and ($u.Department -ne $p.Department -or $u.Title -ne $p.Title))                    { Invoke-Mover $u $p }
   }
   # Orphan check: enabled AD accounts with no HR record at all
   $ad | Where-Object { $_.Enabled -and $_.EmployeeID -notin $hr.EmployeeID } | Export-Csv .\reports\orphans.csv
   ```
3. **Joiner:** create in the department OU, set attributes and manager, add role groups from the matrix, create the home folder with the right ACL, generate a temporary password and send it to the **manager** (in the lab, write it to a protected file), and set `extensionAttribute1 = JML-Managed`.
4. **Mover:** compute `desired groups` from the role matrix, `Compare-Object` with current membership, **remove extras and add missing ones**, and update Department, Title and Manager. Move OU. Log the diff.
5. **Leaver** (order matters):
   1. Record current group memberships to `logs/leavers/<EmployeeID>.json` (needed for rehires and investigations)
   2. Disable the account; reset the password to a random 64-char value
   3. Remove all groups except Domain Users
   4. Set `description = "Leaver <date> ticket #<n>"`, move to `OU=Disabled`
   5. Cloud: `Revoke-MgUserSignInSession -UserId <upn>` (kills refresh tokens), block sign-in, remove licence (after mailbox handling)
   6. Schedule deletion at +90 days (a separate script handles it, with a report first)
6. **Safety features** (interviewers love these):
   - `-WhatIf` dry-run mode that prints planned changes
   - **Circuit breaker:** if more than 10% of accounts would be disabled in one run, abort and alert. This stops a bad HR export from wiping out the company.
   - Everything to `logs/jml-audit.csv` (timestamp, action, target, before, after, operator)
   - Protected list (`data/protected-accounts.txt`): service and break-glass accounts are never touched
7. Schedule with **Task Scheduler** running as a **gMSA** that has *delegated* rights only on the Users/Disabled OUs, **not Domain Admin**. Document the delegation (`dsacls` or the Delegation of Control wizard).

### Phase 2: Stale and privileged account hygiene (Day 6)
```powershell
# Enabled accounts not logged in for 90+ days (lastLogonTimestamp replicates, ~14-day accuracy)
Search-ADAccount -AccountInactive -TimeSpan 90.00:00:00 -UsersOnly | Where Enabled | Select Name,LastLogonDate
# Passwords that never expire, not required, or old
Get-ADUser -Filter {PasswordNeverExpires -eq $true -and Enabled -eq $true}
Get-ADUser -Filter {PasswordNotRequired -eq $true}
# Who is in privileged groups? (recursive)
'Domain Admins','Enterprise Admins','Schema Admins','Administrators','Account Operators','Backup Operators' |
  % { Get-ADGroupMember $_ -Recursive | Select @{n='Group';e={$_}},Name }
```
Create `reports/identity-hygiene-<date>.html` (ConvertTo-Html with CSS). Seed a few bad accounts in the lab first so the "before" report actually finds something.

### Phase 3: Hybrid identity + MFA + Conditional Access (Day 7–10)
1. Add a UPN suffix that matches the verified cloud domain (or use the `onmicrosoft.com` domain in the lab) and update users' UPNs.
2. Install the **Entra Cloud Sync** agent on FS01 (not a DC in production; document why), scope it to `OU=Users,OU=Halden`, and **exclude** `_Admin` and `ServiceAccounts`. **Admin accounts stay cloud-only and are never synced.** That's a standard Tier 0 practice.
3. Create **2 break-glass accounts** (cloud-only, `.onmicrosoft.com`, long random passwords or FIDO2), excluded from all CA policies, with a sign-in alert (P7 monitors it).
4. Conditional Access policies. Start every policy in **Report-only**, review sign-in logs, then turn it **On**:

   | Policy | Users | Condition | Control |
   |---|---|---|---|
   | CA001 – Require MFA – All users | All (excl. break-glass) | All cloud apps | Require MFA |
   | CA002 – Block legacy authentication | All | Client apps: Exchange ActiveSync + other clients | Block |
   | CA003 – Phishing-resistant MFA for admins | Directory roles | All apps | Auth strength: phishing-resistant |
   | CA004 – Block sign-in from unapproved countries | All | Named locations | Block |
   | CA005 – Require MFA to register security info | All | User action: register security info | Require MFA / trusted location |

5. Configure **Authentication methods policy:** Microsoft Authenticator with **number matching**, disable SMS/voice where possible, and enable a **Temporary Access Pass** for onboarding (fits the Joiner flow).
6. Run **ScubaGear before and after**:
   ```powershell
   Install-Module ScubaGear; Initialize-SCuBA
   Invoke-SCuBA -ProductNames aad, exo, teams -OutPath .\evidence\scuba-before
   ```
   Record pass/fail/warning counts in the README.

### Phase 4: Quarterly access review (Day 11–12)
1. `scripts/Export-AccessReview.ps1`: for each department, output **user → groups → resources (shares/apps) → last logon → manager**, one Excel sheet per department (ImportExcel module), with a `Keep / Remove / Change` column.
2. Role-play the review: the "Finance Director" marks 3 removals. You process them through the JML pipeline (a change ticket) and re-export to prove closure.
3. Track in `business/p2-access-review-actions.xlsx`: item, owner, due date, status, evidence link. **This is the "follow up on action items" bullet.**

### Phase 5: Test like an auditor (Day 13)
Run scenarios and record the results in a test log:

| Scenario | Expected result |
|---|---|
| New Sales hire in HR file | Account, groups, home drive created; audit log entry |
| Finance → Operations transfer | Loses Finance share access, gains Operations; old groups gone |
| Leaver with EndDate today | Disabled, sessions revoked, groups captured, moved, ≤15 min |
| Corrupted HR file (50% marked leaver) | **Circuit breaker aborts**, alert raised, nothing changed |
| User signs in with password only | MFA prompt (CA001) |
| IMAP/legacy client sign-in | Blocked (CA002), visible in sign-in logs |

## 7. Business layer (IT Support Officer)

| Artifact | Purpose |
|---|---|
| `business/p2-process-as-is-to-be.pdf` | Swimlane diagrams showing where time and risk were removed |
| `business/p2-role-matrix.xlsx` | Role-based access model signed off by departments |
| `business/p2-mfa-rollout-comms.md` | Staff email + 1-page "How to set up Authenticator" guide + FAQ. Rollout plan: IT → pilot dept → all, with a helpdesk surge plan |
| `business/p2-kpi.md` | Before/after: joiner lead time, leaver revocation time, MFA coverage %, stale accounts, ScubaGear passes |

## 8. Evidence to capture

JML dry-run output · audit CSV · circuit-breaker abort · leaver JSON snapshot · Cloud Sync status · CA policies (report-only → on) · sign-in log showing MFA and a blocked legacy attempt · ScubaGear before/after summary · signed access-review sheet.

## 9. Common pitfalls

- Using names or sAMAccountName as the key. Use `EmployeeID`.
- Running the automation as Domain Admin. Use a delegated gMSA.
- Locking yourself out with CA. That's why you have **break-glass accounts** and **report-only first**.
- Syncing admin accounts to the cloud. Keep them cloud-only or on-prem-only, per tier.
- Deleting leavers immediately. Disable → retain → delete, because of legal holds and rehires.

## 10. Resume bullets (templates)

- Automated the **Joiner-Mover-Leaver** lifecycle for 85 users with PowerShell driven by an HR source-of-truth export, cutting simulated leaver access revocation from **days to under 15 minutes**, with dry-run mode, a mass-change circuit breaker and a full audit trail.
- Deployed **hybrid identity** (AD → Microsoft Entra ID via Cloud Sync) and enforced **MFA for 100% of users** through Conditional Access (report-only → enforce), blocking legacy authentication; improved **CISA ScubaGear** passing checks from **X to Y**.
- Introduced **quarterly access reviews** with department heads, removing **N** excess permissions and tracking every action to closure.

## 11. Interview talking points

- **"How do you stop permission creep?"** A role matrix defines the *desired state*, and the Mover process diffs actual vs desired and removes extras automatically.
- **"What if HR sends a bad file?"** Circuit breaker, dry-run, audit log, and group snapshots to roll back.
- **"How would you roll out MFA without chaos?"** Comms, pilot group, TAP for onboarding, report-only CA, helpdesk surge, break-glass accounts.

## 12. AI-ready build prompt

```text
Act as a senior identity & access management engineer mentoring me on a homelab capstone.
Project: P2 Identity Lifecycle & Access Governance for fictional "Halden Distribution Ltd" (85 users).
Existing (from P1): AD domain ad.halden.internal, OU=Users,OU=Halden with department sub-OUs,
AGDLP groups (G_ role groups, DL_ resource groups), file server FS01. Cloud: Microsoft 365 Business Premium trial
tenant [or Entra ID Free with Security Defaults].

Build with me, phase by phase:
Phase 0 - As-is/to-be JML process map, role matrix, SLAs with HR (give me templates).
Phase 1 - Invoke-HaldenJML.ps1: HR CSV (keyed on EmployeeID) vs AD diff; Joiner/Mover/Leaver functions;
          -WhatIf mode, circuit breaker (>10% disables = abort), protected-accounts list, JSON snapshot of leaver
          groups, CSV audit log, runs as a delegated gMSA (show the delegation steps).
Phase 2 - Stale/privileged account hygiene report as HTML.
Phase 3 - Entra Cloud Sync scoping (exclude admin OUs), 2 break-glass accounts, Conditional Access
          policies CA001-CA005 in report-only then on, Authenticator number matching, Temporary Access Pass,
          ScubaGear before/after.
Phase 4 - Export-AccessReview.ps1 producing one Excel sheet per department + action tracker.
Phase 5 - Test plan with the 6 scenarios (including a corrupted HR file).
Rules: production-quality PowerShell (functions, comment-based help, try/catch, logging, no secrets in code).
After each phase tell me what evidence to screenshot. Finish with README, KPI table and resume bullets
using my real numbers. Start with Phase 0.
```
