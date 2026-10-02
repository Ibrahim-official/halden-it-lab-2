# Runbook — Restore a whole VM or server

**Duty:** Systems · **Time:** 30–90 minutes · **Applies to:** DC01, DC02, FS01, LNX01, OPS01, SIEM01
**Audience:** someone who did not build the backup system.

> Restoring a whole server is a change, not a file copy. **Tell the business first**, take a snapshot
> of the current (broken) VM for evidence, and restore into the **sandbox** before it touches the
> production network.

## 0. Safety checks before you touch anything

1. **Is the original VM still there?** Keep it (powered off) as evidence. Do not overwrite it in place.
2. **Sandbox first.** Restore to a scratch VM id / name (e.g. VM `9001` or `RESTORE-TEST`) attached to
   the **isolated bridge with no uplink** (VLAN 99). Only promote it to production after it boots
   clean and, for a DC, after it has been scanned.
3. **Which restore point?** Pick one that is *before* the event you are recovering from (see the SIEM
   timeline in the ransomware runbook). Never restore a compromised image straight to production.
4. **Tombstone lifetime (DCs only):** never restore a domain controller from a backup older than the
   tombstone lifetime (180 days). Record the backup's age.

## 1. Find the restore point

```bash
# File-level repository (on BKP01)
restic snapshots --host <original-host>   # note the snapshot id and timestamp
```

For VM-level backups produced by `02-Backup-HyperVVMs.ps1`, the export is a folder per host per date;
list it on HOST01:

```powershell
Get-ChildItem "$env:BACKUP_STAGE\<host>" | Sort-Object Name -Descending | Select-Object -First 10
```

## 2. Restore into the sandbox

**File-level (rebuild a Linux server offline):**

```bash
mkdir -p /srv/restore-scratch/<host>
restic restore <snapshot-id> --target /srv/restore-scratch/<host>
# then copy into the clean rebuilt VM over a private link, or attach the disk to the sandbox VM
```

**VM-level (Hyper-V, on HOST01):**

```powershell
# Import the exported VM into a sandbox, NOT the production switch
Import-VM -Path "$env:BACKUP_STAGE\<host>\<date>\<host>.vmcx" -Copy -GenerateNewId
Set-VM -Name '<host>-restore' -AutomaticStartAction Nothing
Connect-VMNetworkAdapter -VMName '<host>-restore' -SwitchName 'Halden-Sandbox'   # no uplink (VLAN 99)
Start-VM -Name '<host>-restore'
```

## 3. Verify the restored system (the real test)

| System | Health check | Expected |
|---|---|---|
| DC01/DC02 | `dcdiag /q`, `repadmin /replsummary`, `Get-Service NTDS,DNS,Netlogon` | clean, services running |
| FS01 | open each share as a test user; compare ACLs to `configs/p01-*` | shares reachable, permissions as designed |
| LNX01 | does the order app answer on its port? can it read its database? | app responds, data present |
| OPS01 | GLPI and Uptime Kuma respond | web UIs load |
| SIEM01 | Wazuh dashboard loads, agents report | dashboard up |

Record how long the whole step took — that number feeds the DR drill timing table.

## 4. Promote to production (only after it passes)

1. **For a DC:** scan the restored VM in the sandbox (offline AV / a known-clean baseline) before it
   joins the production network. Then:
   - decide **authoritative vs non-authoritative** restore before you connect it;
   - connect to the production switch, verify replication with `repadmin /showrepl`;
   - reset privileged passwords and rotate **krbtgt twice** if this is a compromise recovery.
2. **For a member server (FS01/LNX01/OPS01/SIEM01):** point the test client at the restored VM, run the
   service test again on the production network, then swap it into service.
3. Keep the old broken VM powered off as evidence until the incident is closed.

## 5. Clean up and roll back

- Scratch VM: `Stop-VM '<host>-restore' -TurnOff; Remove-VM '<host>-restore' -Force` and delete its
  disk. **Deleting the scratch environment is the rollback for a restore test** — nothing in
  production was changed.
- Restore scratch folder on BKP01: delete `/srv/restore-scratch/<host>` after the incident is closed.
- Log: host, restore point, time taken, verdict, and any gap between target and actual recovery.

## 6. When to escalate

- The restored system boots but the **data is wrong or missing** → the restore point is wrong; try an
  older one, and check whether the offsite copy has a better one.
- The restore **exceeds the RTO** for that tier → treat as a process failure and raise it in the
  lessons-learned review.
- A DC restore is involved → follow the AD recovery runbook and the forest-recovery sequence; do not
  improvise a single-DC restore without checking replication health first.

> **Lab practice:** the VM-level commands assume Hyper-V exports on HOST01. On a Proxmox lab, replace
> them with `qmrestore <backup-id> 9001 --storage local-lvm --unique 1` and `qm set 9001 --net0
> virtio,bridge=vmbr99`. Do not claim a restore succeeded until the health checks above have passed.
