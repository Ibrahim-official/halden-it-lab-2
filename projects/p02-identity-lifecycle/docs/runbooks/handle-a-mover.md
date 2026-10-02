# Runbook — A member of staff changes role (mover)

**Applies to:** DC01 · **Target:** same day · **Owner:** IT Support
**Raised by:** HR (new role approved by the receiving department head)

> Why this matters: permission creep — keeping the old department's access after a move — is how an
> organisation ends up unable to answer "who can see Finance data?". The mover path exists to remove
> the old access at the same moment it grants the new access.

1. **Confirm the move in writing.** HR supplies the employee number, the new department, the new
   title and the effective date. The **receiving** department head approves the new access; the
   **previous** department head is told so they know the old access is ending.
2. **Update the HR export.** Change `Department` and/or `Title` on that person's row. Nothing else —
   do not edit group memberships by hand.
3. **Check the destination role exists in the matrix.** `configs/role-matrix.csv` must have a row for
   the new `Department,Title`. If it does not, agree the access with the receiving head and add the
   row **before** the change — do not run with an unknown role and fix it afterwards.
4. **Snapshot DC01** — `snap-p2-ph1-before`.
5. **Preview the diff** (`-WhatIf` changes nothing):
   ```powershell
   .\scripts\01-Invoke-HaldenJML.ps1 -EmployeeID '<EmployeeID>' -WhatIf
   ```
   The plan must show the **groups to remove** (the old role) and the **groups to add** (the new
   role) in the same run, plus the attribute and OU changes.
6. **Run it for real:**
   ```powershell
   .\scripts\01-Invoke-HaldenJML.ps1 -EmployeeID '<EmployeeID>'
   ```
7. **Confirm the mover landed correctly** — old role gone, new role present, `G_AllStaff` retained:
   ```powershell
   $u = Get-ADUser -Filter "EmployeeID -eq '<EmployeeID>'" -Properties MemberOf,Department,Title
   $u | Select-Object SamAccountName,Department,Title,DistinguishedName
   (Get-ADPrincipalGroupMembership $u).Name | Sort-Object
   ```
8. **Ask the user to sign out and back in.** Group membership is applied at logon, so the mapped
   drives change then. Confirm the user can open the new department's folder **and can no longer open
   the old one**.
9. **Update the ticket** with what was added, what was removed and who approved it. This diff is
   exactly what the quarterly access review reads.

**Note on scope:** the mover only removes the role groups it knows about from the matrix (plus
`G_AllStaff` handling). Any group that represents a separate approval — for example a project
distribution list — is left alone and reported, not guessed at. That is deliberate: an automated
tool should not silently revoke an access nobody asked it to manage.

**Rollback:** the change is a group and attribute change. Re-add the groups from the previous
department (you have them in the audit log's "before" column), correct the HR export back to the old
role, and re-run the engine — or revert the `snap-p2-ph1-before` snapshot if the change was wider
than one person.
