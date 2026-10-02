# Runbook — Deploy and validate Windows LAPS

**Applies to:** DC01 (deployment) and every workstation/member server (validation) ·
**Time:** about 2 hours plus a Group Policy refresh · **Owner:** IT / Systems

## Why

One local administrator password, shared across every workstation, is the single shortest path from
one phished laptop to the whole domain: the attacker only has to learn it once. Windows LAPS removes
that path by giving every endpoint its own unique, rotating password, backed up to Active Directory
and encrypted, with read access delegated to exactly one group. The plan's success criterion is that
**100% of workstations and member servers** have a unique, rotating password — which is a claim that
needs a test, not a tick.

## 1. Before you start

| Step | Command | Notes |
|---|---|---|
| Snapshot DC01 and DC02 | `snap-p3-ph3-before` | **`Update-LapsADSchema` changes the forest schema and cannot be undone by deleting an attribute.** Snapshot both DCs together |
| Confirm schema rights | whoami /groups | `Update-LapsADSchema` needs Schema Admin |
| Confirm the groups exist | `Get-ADGroup G_Tier2_Helpdesk, G_Tier1_ServerAdmins, G_Tier0_Admins` | Created in Phase 4; the script skips read delegation if a group is missing |
| Confirm the endpoints are in the right OUs | `Get-ADComputer -Filter * | Select Name, DistinguishedName` | LAPS permission is applied per OU |

## 2. Deploy

```powershell
.\scripts\06-Deploy-Laps.ps1 -WhatIf          # preview every change first
.\scripts\06-Deploy-Laps.ps1                  # apply
```

What it does, in order:

1. `Update-LapsADSchema` (skipped if the `ms-LAPS-Password` attribute already exists).
2. Grants computers the right to write their own password, on the Workstations and Servers OUs.
3. Grants the helpdesk read access on workstations and the server admins on servers.
4. Creates `WKS - LAPS - v1`, `SRV - LAPS - v1` and `DC - LAPS - v1` exactly as specified in
   `configs/p03-laps-gpo-settings.conf`, including encrypted backup, a 30-day rotation, an 8-hour
   post-authentication reset, and DSRM password backup for the DCs.

Then refresh policy on the endpoints:

```powershell
Invoke-Command -ComputerName WS01,FS01 -ScriptBlock { gpupdate /force }
```

## 3. Validate — the part that actually proves it

| Check | Command | Expected |
|---|---|---|
| Password backed up | On a DC: `Get-WinEvent -LogName 'Microsoft-Windows-LAPS/Operational' | Where-Object Id -eq 10018 | Select -First 5` | Event 10018 present for the endpoint |
| Password readable by helpdesk | As a `G_Tier2_Helpdesk` member: `Get-LapsADPassword -Identity WS01 -AsPlainText` | Returns the password with `DecryptionStatus = Success` |
| Password **denied** to a normal user | As a standard Sales account: `Get-LapsADPassword -Identity WS01 -AsPlainText` | Denied — this is the control that matters |
| Encryption is on | `Get-LapsADPassword -Identity WS01 -AsPlainText:$$false` | `DecryptionStatus = Encrypted` when read without a decryptor |
| Rotation is configured | `Get-LapsADPassword -Identity WS01` | `PasswordUpdateTime` and a 30-day `ExpirationTimestamp` |
| Coverage | `Get-ADComputer -Filter * -Properties msLAPS-PasswordExpirationTime | Where-Object { -not $_.'msLAPS-PasswordExpirationTime' }` | Empty on the endpoints in scope |

**Screenshot rule:** when you screenshot the successful helpdesk read, **blur or crop the password
value itself**. A published LAPS password is a working credential (AGENTS.md 4.6). The evidence that
matters is that the read succeeded for the right group and failed for the wrong one.

## 4. DSRM backup for domain controllers

The `DC - LAPS - v1` GPO enables DSRM password backup, so the Directory Services Restore Mode
password is no longer a manually managed secret nobody remembers. Validate it the same way as any
other LAPS password, using the Tier 0 group as the decryptor.

## 5. If it does not work

| Symptom | Likely cause | Action |
|---|---|---|
| No event 10018 | Policy not applied, or the endpoint is not in the OU the GPO is linked to | `gpresult /h` on the endpoint; check the OU path |
| `Get-LapsADPassword` fails for helpdesk | Read permission not delegated, or the wrong group name | Re-run `06-Deploy-Laps.ps1` and check `Get-LapsADReadPasswordPermission` |
| A normal user can read the password | Read permission is too broad — **a genuine finding** | Remove the broad ACE immediately and record it as a finding in the register |
| The managed local account does not exist | No managed account name was configured | Check the `AdministratorAccountName` setting in `WKS - LAPS - v1` |

## Rollback

- **Before the schema change:** revert the DC01 and DC02 snapshots together.
- **After the schema change:** the attribute cannot be removed cleanly. Roll back the *policy*
  instead: unlink or delete the three LAPS GPOs, run `gpupdate /force`, and return the local
  administrator password to its previous manual process. Record in `DECISIONS.md` that the schema
  extension remains.

> This is a lab procedure for a fictional company. In production, every step of the schema change
> happens in a change window with a tested forest backup and a rollback that has been rehearsed.
