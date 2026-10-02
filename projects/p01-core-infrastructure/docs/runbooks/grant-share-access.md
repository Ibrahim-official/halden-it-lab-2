# Runbook — Grant or remove access to a share

**Applies to:** DC01 (group membership) and FS01 (permissions) · **Time:** 5 minutes · **Owner:** IT Support

**Golden rule:** permissions are granted to **groups only**. Never put a person on a folder ACL.
"Just this once" is how an organisation ends up with thousands of unexplained permissions.

1. **Confirm the approval.** A share request needs the department head's approval. Read-only
   access for directors is already covered by the existing `DL_…_RO` groups — check the permission
   matrix (`business/p01-permission-matrix.md`) before changing anything.
2. **Decide the smallest change.** Most requests are one of:
   - person moves department → replace their `G_<OldDept>_Staff` membership with `G_<NewDept>_Staff`
     (do **not** leave both);
   - person needs read-only access to another department → ask the owning department head, then add
     the person to that department's `G_` group only if a read-only `DL_…_RO` group exists;
   - a whole new share or a new access level is needed → that is a change, not a request; raise it
     through the change process and update the permission matrix.
3. **Make the change on DC01:**
   ```powershell
   # add
   Add-ADGroupMember  -Identity G_Finance_Staff -Members sara.khan
   # replace (mover: leave the old role behind)
   Remove-ADGroupMember -Identity G_Sales_Staff -Members sara.khan -Confirm:$false
   ```
4. **Prove it.** Ask the user to sign out and back in (group membership is evaluated at logon for
   mapped drives), then confirm they can open the folder — and cannot open the one they lost:
   ```powershell
   # what can this account reach?
   (Get-Acl \\fs01.ad.halden.internal\Finance).Access |
     Where-Object { $_.IdentityReference -like '*DL_*' } |
     Select-Object IdentityReference, FileSystemRights
   ```
5. **Run the ACL audit** after any permission change on FS01 and confirm it still reports
   **0 violations**:
   ```powershell
   .\scripts\07-Test-ShareAcl.ps1
   ```
6. **Update the ticket** with what was granted, who approved it and the date — that audit trail is
   what P2's access review reads.

**Rollback:** remove the membership you added (`Remove-ADGroupMember`). Nothing else was changed.
