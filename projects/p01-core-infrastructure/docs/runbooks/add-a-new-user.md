# Runbook — Add a new Halden user

**Applies to:** DC01 · **Time:** 5 minutes · **Owner:** IT Support · **Raised by:** HR (approved by the department head)

1. **Get the request in writing.** HR confirms: full name, department, job title, start date,
   office (HQ or WAREHOUSE), and who their manager is. Access is approved by the department head,
   not by IT.
2. **Add the person to the HR file.** Append one row to `data/halden-staff.csv`
   (`First,Last,Department,Title,Manager,Office,EmployeeID,StartDate`). Keep the file as the
   single source of truth — do not create the account by hand in ADUC.
3. **Snapshot DC01** (or confirm a recent one exists) — `snap-p1-ph4-before`.
4. **Preview the change** (nothing is created with `-WhatIf`):
   ```powershell
   .\scripts\04-Import-HaldenUsers.ps1 -WhatIf
   ```
   Check the script reports exactly one new user and no unexpected rows.
5. **Run it for real:**
   ```powershell
   .\scripts\04-Import-HaldenUsers.ps1
   ```
   The user is created in the right departmental OU, added to their `G_<Dept>_Staff` and
   `G_AllStaff` groups, given a random password that must be changed at first logon, and their
   manager is set. The audit line is appended to `logs/import-<date>.csv`.
6. **Hand over the credentials securely.** Take the initial password from
   `logs/initial-passwords-<date>.csv` (this file is git-ignored) and give it to the user through
   the agreed secure channel — never by email in clear text. Delete the row from the file once the
   user has signed in and changed it.
7. **Check the folder access.** The user gains the right drive letters automatically at next logon
   through their `G_` group. If the role needs an unusual folder, add the user to the matching
   `G_` group — never place a user directly on a folder ACL.
8. **Close the ticket** and note the EmployeeID. Re-running the script later is safe: existing
   users are skipped, not duplicated.

**Rollback:** `Disable-ADAccount <sam>` (and move to `OU=Disabled`). Deleting is a last resort and
is only done with the department head's confirmation.
