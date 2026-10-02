# Runbook — Restore a file from a previous version (user-facing)

**Duty:** IT Service Desk · **Time:** 2 minutes · **Applies to:** all staff on the file share

## What the user can do themselves (no ticket needed)

This is the point of the twice-daily shadow copies: the user restores their own file in under a
minute, without waiting for IT.

1. Open **File Explorer** and go to the folder where the file used to be
   (e.g. `G:\Shared` or their department share `F:\`).
2. Right-click in the folder (on the folder itself, not the file) and choose
   **Properties → Previous Versions**.
   On Windows 11 this tab may be labelled **"Previous versions"** and, if missing, is available
   from **Restore previous versions** in the right-click menu.
3. The list shows the available snapshots — normally **07:00** and **12:00** each day.
   Pick the one from before the file was lost or changed, and select **Open** to look inside it
   (this is a safe, read-only preview — nothing is restored yet).
4. Find the file, then either:
   - **copy** it out to the desktop and check it, then move it back into place; or
   - select **Restore** to put it back in its original location (this overwrites the current
     version — if a colleague has been editing it, copy instead of restore).
5. Confirm the file opens correctly **before deleting anything**.

**Important:** Previous Versions only covers files on the file server (the `F:`, `H:`, `S:`, `O:`
and `G:` drives). Files on a local desktop or in OneDrive are not covered by this and are handled
by the backup service (P8).

## What the Service Desk does when the user cannot

1. Ask **which folder, which file, and roughly when it was last good** — the snapshot list only
   offers what exists, so the time matters.
2. If the snapshot is not visible from the user's PC, check from the file server itself:
   ```powershell
   # what snapshots exist?
   vssadmin list shadows /for=C:
   ```
3. Once the right shadow copy is identified, restore the file for the user and confirm it opens:
   ```powershell
   # expose a shadow copy read-only and copy the file back (run on FS01)
   $s = (Get-CimInstance Win32_ShadowCopy | Sort-Object InstallDate -Descending | Select-Object -First 1).DeviceObject
   cmd /c mklink /d C:\_shadow "$s\"
   Copy-Item "C:\_shadow\Shares\Finance\budget.xlsx" "C:\Shares\Finance\budget.xlsx" -Force
   ```
   Remove `C:\_shadow` when finished so it is not left as an unexpected path.
4. Tell the user what was restored and when, and close the ticket.

## When to escalate

- **No snapshot from before the loss** (older than the oldest shadow copy) → this needs the real
  backup service; raise it as a restore request and record the recovery point actually required.
  That gap is evidence for the backup design in P8.
- **A whole folder or share is missing** → treat as an incident, not a service request.
- **The file was deleted by a person, not by accident** → involve the line manager before restoring.
