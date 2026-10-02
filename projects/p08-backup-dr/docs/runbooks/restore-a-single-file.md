# Runbook — Restore a single file or folder

**Duty:** IT Service Desk / Systems · **Time:** 5–15 minutes · **Applies to:** any file protected by P8
**Audience:** someone who did not build the backup system.

## 0. Before you start — three questions

1. **Which file or folder?** Get the exact path and name.
2. **When was it last correct?** This chooses the restore point. "Yesterday morning" is enough.
3. **Is it still on the live server?** If a colleague has been editing it, restore to a **different
   location** first and let the owner copy it back — never overwrite live data blindly.

> Shadow copies (P1) handle the last few hours on the file server and need no IT. Use this runbook
> when the file is gone from the shadow copies, is on a different system, or the user wants IT to do it.

## 1. Find the right snapshot (on BKP01)

```bash
sudo -i
source /etc/halden-lab/backup.env                 # uncommitted; holds paths, not printed secrets
restic snapshots --host <hostname> --tag <tier>   # list restore points for the system
```

Pick the snapshot id from **at or just before** the time the file was last good. If unsure, choose an
older snapshot: restoring an older copy is safe, restoring a wrong-but-newer one can confuse things.

## 2. Restore to a scratch location (never over live data)

```bash
restic restore <snapshot-id> \
  --include "/srv/data/Finance/budget-2026.xlsx" \
  --target /srv/restore-scratch/$(date +%F)
```

- `--include` takes the exact path **as it was inside the snapshot** (use `restic ls <id> | grep <name>`
  if you need to confirm it).
- Restoring to a scratch folder means nothing live is touched. Clean it up when done.

**On Windows (FS01), from an elevated shell:**

```powershell
restic.exe -r $env:RESTIC_REPOSITORY restore <snapshot-id> --include "C:\Shares\Finance\budget-2026.xlsx" --target C:\_restore
```

## 3. Check the file before handing it over

1. Open the restored file and confirm it is the expected version (check the content, not just size).
2. Compare the checksum against the source hash manifest written at backup time (optional but strong):
   ```bash
   sha256sum /srv/restore-scratch/2026-10-02/srv/data/Finance/budget-2026.xlsx
   ```
3. Tell the user what you restored, **from which restore point**, and where you put it.

## 4. Put it back

- **Preferred:** give the user the restored copy to place themselves, so they confirm the content.
- If IT must overwrite, copy the **existing** file aside first, then restore over it; keep the aside
  copy until the user confirms.
- Delete the scratch folder afterwards so it is not left behind.

## 5. If the file is not in any snapshot

1. Check the retention policy: the file may simply be older than the retention window
   (`configs/p08-retention-policy.md`).
2. Try the **offline USB** copy (last resort) — see the DR runbook for the rotation log location.
3. If it genuinely does not exist anywhere, record the gap honestly: what was asked for, what the
   oldest available restore point was, and how far outside retention it fell. That gap is evidence for
   a retention change, not something to hide.

## 6. After every restore request

- Log: requester, path, restore point used, where it was put, time taken.
- If the request was because a file was **deleted by a person**, involve the line manager before
  restoring — the same rule as P1's shadow-copy runbook.
- If the same file keeps needing restores, that is a process problem worth raising, not just a ticket.

> **Lab practice:** the command paths above are the design. Do not claim a restore request was handled
> until a real restore has been performed from a real snapshot.
