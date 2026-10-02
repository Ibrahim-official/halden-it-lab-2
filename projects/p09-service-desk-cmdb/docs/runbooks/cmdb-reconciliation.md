# Runbook — Run the CMDB reconciliation and drift check

**Applies to:** DC01 (as the PowerShell host) and OPS01 (GLPI) · **Time:** 10–20 minutes
**Owner:** IT / Systems · **When:** weekly, and after any bulk asset change (deployment, disposal)

## Why

An asset register is only true on the day it is reconciled. This weekly job compares the CMDB
against the live network and the P1 domain and surfaces two things that matter:

- **Unknown-OnNetwork** — a device on the network that is *not* in the CMDB. This is a security
  problem (an unmanaged device) as much as a records problem.
- **Stale / orphan records** — CMDB or DNS entries for devices that no longer exist.

The target is **0 unknown-on-network**; anything else is a finding to clear before the week ends.

## 0. Before you start

- Snapshot: not required — both scripts are read-only.
- GLPI tokens: set `GLPI_APP_TOKEN` and `GLPI_USER_TOKEN` in the session (values from the password
  manager), **or** export the CMDB to CSV and pass `-CmdbCsv`.
- `nmap` must be available on the Windows host running the sweep (or run only the DHCP/AD/DNS parts
  and import the sweep results separately).

## 1. Reconciliation against DHCP and the network

```powershell
# On DC01 (or a management host with RSAT + nmap)
$env:GLPI_APP_TOKEN = '<from password manager>'
$env:GLPI_USER_TOKEN = '<from password manager>'
.\scripts\02-Test-AssetReconciliation.ps1 -Subnets 192.168.10.0/24 `
  -Report ..\evidence\raw\p09-ph1-reconciliation-result.csv
```

Expected output: a count line and a CSV with a `Status` column of `Matched`,
`Unknown-OnNetwork` or `Stale-InGlpi`. **The exit code is the number of unknown-on-network
devices** — a clean run exits 0.

## 2. Drift check against AD, DNS and DHCP

```powershell
.\scripts\05-Test-CmdbDrift.ps1 -CmdbCsv ..\evidence\raw\glpi-assets.csv `
  -Report ..\evidence\raw\p09-ph5-cmdb-drift-result.csv
```

This classifies drift into `Missing-InCmdb`, `Orphan-InCmdb`, `DnsWithoutHost` and
`Reserved-NotLeased`. Exit code = total drift rows.

## 3. Clear the findings

| Finding | Action |
|---|---|
| Unknown-OnNetwork | Identify it (`ping -a`, MAC lookup), decide if it is a legitimate lab device, add it to the CMDB (or isolate it if it should not be there). |
| Stale-InGlpi / Orphan-InCmdb | Confirm retirement with the owner, then set the asset to **Retired** or **Disposed** (never delete: history matters). |
| DnsWithoutHost | A stale A record — confirm scavenging is on and remove the record if the host is gone. |
| Reserved-NotLeased | A reservation nobody is using — confirm the device is decommissioned, then release the reservation. |

Remediation is **manual and reviewed**: the scripts report, they do not delete records.

## 4. Record the result

Save the CSV to `evidence/public/` (sanitized) and update the reconciliation metric in `README.md`
with the real numbers. The weekly target is 0 unknown-on-network; if it is not reached, the finding
and its cause belong in the ticket, not hidden.

## 5. Rollback

Nothing was changed by the scripts. If a manual remediation was wrong (a device retired by
mistake), set its status back and note the correction in the ticket — the change history is the
audit trail.

> Not yet run: this is the procedure, and the reconciliation result is recorded only once the lab
> run has actually produced it.
