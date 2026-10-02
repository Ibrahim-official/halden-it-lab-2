# Runbook — Onboard a new starter

**Applies to:** DC01 (and FS01 for the home folder) · **Target:** ready before day 1 · **Owner:** IT Support
**Raised by:** HR (access approved by the hiring department head)

> Why this matters: a new starter's first morning should not be spent waiting for IT. Because the
> account is built from the HR record and the role matrix, "ready by day −1" is a property of the
> process, not a promise someone has to remember.

1. **Confirm the request in writing.** HR supplies: full name, department, job title, start date,
   office (HQ or Warehouse), and the employee number. Access is approved by the **department head**,
   not by IT.
2. **Add the person to the HR export.** Append one row to `data/hr-export.csv` with `Status = Active`
   and the `StartDate`. Keep the file as the single source of truth — do not create the account by
   hand in ADUC.
3. **Check the role exists in the matrix.** `configs/role-matrix.csv` maps `Department,Title` to the
   `G_` role groups. An exact title match is used first; the `Department,*` row is the department
   default. If the title needs a different set, that is a change to the matrix, approved like any
   other access change — do not add the groups by hand afterwards.
4. **Snapshot DC01** (and FS01 if the home folder step runs) — `snap-p2-ph1-before`.
5. **Preview the change** (nothing is created with `-WhatIf`):
   ```powershell
   .\scripts\01-Invoke-HaldenJML.ps1 -EmployeeID '<EmployeeID>' -WhatIf
   ```
   The plan must show exactly one `Joiner` for this person and no unexpected rows. Read the planned
   groups against the role matrix.
6. **Run it for real:**
   ```powershell
   .\scripts\01-Invoke-HaldenJML.ps1 -EmployeeID '<EmployeeID>'
   ```
   The engine creates the account in the department OU, sets department/title/manager/`EmployeeID`,
   stamps `extensionAttribute1 = JML-Managed`, adds the role groups, and creates the home folder on
   FS01 with access for that user only.
7. **Hand over the first credential securely.** The initial password is random, must be changed at
   first logon, and is written only to the git-ignored `logs/initial-passwords-<date>.csv`. Give it
   to the **line manager** over the agreed secure channel — never by clear-text email. Delete the row
   once the person has signed in and changed it. If hybrid identity is live, a **Temporary Access
   Pass** is the preferred method instead of a password.
8. **Check access.** The user gains their drives at next logon through their role groups. If the role
   needs an uncommon folder, add the user to the matching `G_` group — never place a user directly on
   a folder ACL.
9. **Close the ticket** and quote the `EmployeeID`. Re-running the engine is safe: an existing
   account is skipped, not duplicated.

**Verification:** the audit log has a dated `Joiner` record; the account is enabled in the correct
OU; its groups match the role matrix; the home folder exists.

```powershell
$u = Get-ADUser -Filter "EmployeeID -eq '<EmployeeID>'" -Properties MemberOf,Enabled,extensionAttribute1
$u | Select-Object SamAccountName,Enabled,extensionAttribute1
(Get-ADPrincipalGroupMembership $u).Name
```

**Rollback:** `Disable-ADAccount <sam>` and move the account to `OU=Disabled`, or delete it if the
hire was cancelled — with the department head's confirmation. Deleting is a last resort.
