# Runbook — Full disaster recovery drill (and real recovery)

**Document owner:** IT Lead · **Approvers:** Managing Director + IT Lead · **Applies to:** all Halden systems
**Written for:** someone who did **not** build this lab. Every step says what to expect so you can tell
whether it worked without asking the author.

> **Print this document and store a copy off-site** with the offline USB. In a real disaster the wiki,
> the file server and the intranet may all be unavailable — the runbook must not depend on the systems
> it recovers.

---

## A. What you need before you start

| Item | Where it is | Notes |
|---|---|---|
| Hypervisor console | HOST01 (Windows 11 Pro, Hyper-V) | local console or a physical keyboard/monitor |
| BKP01 credentials | owner password manager | **not** domain credentials — BKP01 is not domain-joined |
| Repository passphrase | password manager **and** sealed offline copy | read from `/etc/halden-lab/backup.env` on BKP01 |
| Object-store (MinIO/S3) keys | password manager; uncommitted env on BKP01 | used by `restic copy` |
| Offline USB passphrase | sealed envelope with the offline copy | last-resort medium |
| Firewall config | Git (config-as-code, P9) + the offline copy | rebuild FW01 from this |
| This runbook | printed, off-site | you are reading it |

**Roles** (one person may hold several in a small company; write down who actually holds them):

| Role | Responsibility |
|---|---|
| Disaster declared by | Managing Director **with** IT Lead |
| Incident lead | IT Lead — runs the recovery, owns the clock |
| Backup/recovery operator | Systems — BKP01, restic, restores |
| Business liaison | department heads — confirm their systems work before "all clear" |
| Communications | MD or office manager — staff and customer updates |

**Contact steps:** call the IT Lead first, then the MD (decides on business impact and spend), then the
department heads (verify their systems), then vendors (offsite storage, ISP) only if the incident needs
it. Use the contact list in `business/p08-dr-plan.md`; keep a printed copy with this runbook.

---

## B. Decision tree — what happened?

```
Is it one file or folder lost?            → restore-a-single-file.md (5–15 min)
Is it one server failed/corrupted?        → restore-a-whole-vm.md (30–90 min)
Is AD deleted-object damage only?         → ad-recovery: AD Recycle Bin (online)
Is AD damaged in bulk / older change?     → ad-recovery: authoritative restore in DSRM
Is it ransomware / the backups at risk?   → ransomware-immutability.md FIRST, then this runbook
Is it the whole site / host lost?         → this runbook, from step 0
Was the backups' integrity affected?      → this runbook, and recover from Copy 2 / the offline USB
```

**Declare a disaster when:** two or more Tier 0/1 systems are down, or a Tier 0/1 system is expected to
be down beyond its RTO, or AD/backup integrity is in doubt. Do not wait for certainty; declare and
stand down if it turns out smaller.

---

## C. Recovery order with dependencies

Recover in this order. Each step depends on the one before it — AD gives identity, identity gates the
rest, file services come before the applications that need them.

```
0. Declare disaster, start IR (P7), preserve evidence, isolate the network
1. Clean infrastructure: hypervisor, then FW01 (config from Git / offline copy)
2. BKP01 health check; choose a restore point BEFORE the compromise (SIEM timeline)
3. DC01 restore (sandbox first; scan; then promote) → verify DNS and DHCP
4. Reset krbtgt x2, privileged passwords, service accounts, LAPS rotation
5. FS01 restore → share access tested with a Finance user
6. LNX01 order app → functional test with a Sales user
7. OPS01 (GLPI, Uptime Kuma), SIEM01 (Wazuh)
8. Re-image workstations from the standard build → users back to work
9. Hand back to the business; lessons-learned review
```

**Decision points** (record the choice and who made it):

| Decision | Default | Who decides |
|---|---|---|
| Restore in place vs rebuild fresh | Rebuild fresh for anything compromised; restore for hardware failure | Incident lead |
| Which restore point | Newest snapshot older than the first suspicious event | Incident lead + SIEM timeline |
| Sandbox-scan before promoting a DC | Always scan first on a compromise | Incident lead |
| Accept data loss vs wait longer | Compare actual data loss against the agreed RPO | MD + business liaison |

---

## D. Step-by-step

### Step 0 — Declare, contain, preserve
- MD and IT Lead declare the disaster and start the clock. **Write down the start time.**
- Isolate affected systems (network disconnect / VLAN 99 with no uplink). **Do not power them off.**
- Preserve evidence before cleaning. Open the IR process (P7) and get the SIEM timeline if SIEM01 is
  still usable.
- **Expected outcome:** everyone knows it is a disaster, the clock is running, evidence is safe.

### Step 1 — Clean infrastructure
- Confirm the hypervisor boots and its management console is reachable.
- Rebuild FW01 from its committed config (Git). Verify it comes up with the expected interfaces/rules.
- **Expected outcome:** the platform and the perimeter exist and are clean.

### Step 2 — BKP01 health check and restore-point choice
- On BKP01: `restic snapshots --last` (on-site) and `restic -r "$OFFSITE_REPOSITORY" snapshots --last`
  (offsite). Both must list recent snapshots.
- Confirm the immutable bucket still holds the repository (`mc ls --versions`).
- Pick the restore point (Decision table). Record the snapshot id and timestamp.
- **Expected outcome:** a named, pre-compromise restore point and a healthy repository.

### Step 3 — Restore DC01 (sandbox first)
```bash
# On BKP01: restore the DC's file-level data / stage the VM export for HOST01
restic snapshots --host DC01
```
```powershell
# On HOST01: import to the sandbox switch (no uplink), boot, scan
Import-VM -Path "$env:BACKUP_STAGE\DC01\<date>\DC01.vmcx" -Copy -GenerateNewId
Connect-VMNetworkAdapter -VMName 'DC01-restore' -SwitchName 'Halden-Sandbox'
Start-VM -VMName 'DC01-restore'
```
- Health check: `dcdiag /q`, `repadmin /replsummary`, `Get-Service NTDS,DNS,Netlogon`.
- If restoring via system state instead: boot to **DSRM**, `wbadmin start systemstaterecovery`, then
  decide authoritative vs non-authoritative before reconnecting.
- Promote to production only after it is clean. Verify DNS resolves and DHCP leases are issued.
- **Expected outcome:** a working, scanned DC serving AD, DNS and DHCP. **Time this step.**

### Step 4 — Burn the compromised credentials
- Reset **krbtgt twice** with a replication cycle between resets.
- Reset privileged account passwords, service accounts (gMSA where possible) and rotate LAPS.
- Reset the DC computer account password and any trust passwords.
- **Expected outcome:** the attacker's golden/silver tickets are worthless; new credentials issued.

### Step 5 — Restore FS01
- Restore to the sandbox, verify shares and ACLs, then promote.
- Test as a **Finance** user: open the Finance share, confirm HR is not visible (ABE).
- **Expected outcome:** departmental shares work for the right people. **Time this step.**

### Step 6 — Restore LNX01 (order app + database)
- Restore the app and database, start the service, confirm the app answers on its port.
- Test with a **Sales** user: take a test order end-to-end.
- **Expected outcome:** orders can be taken again. **Time this step.**

### Step 7 — Restore OPS01 and SIEM01
- OPS01: GLPI and Uptime Kuma respond; Uptime Kuma starts receiving the backup heartbeat again.
- SIEM01: Wazuh dashboard loads and agents reconnect.
- **Expected outcome:** service desk and monitoring are back.

### Step 8 — Re-image workstations
- Rebuild WS01/WS02 class machines from the standard build; users sign in and reach their redirects.
- **Expected outcome:** users can work.

### Step 9 — Hand back and review
- Business liaison confirms each department's system; MD issues the "all clear".
- Stop the clock: total recovery time recorded per system against its RTO target.
- Lessons-learned review: what broke, what was fixed, actions with owners and dates.

---

## E. Recovery-time table (fill in during the drill)

| System | RTO target | Actual | RPO target | Actual data loss | Pass? | Notes / fix |
|---|---|---|---|---|---|---|
| DC01 (AD/DNS/DHCP) | 2 h | | 24 h | | ☐ | |
| FS01 (Finance/Sales) | 4 h | | 1 h | | ☐ | |
| LNX01 (order app + DB) | 4 h | | 1 h | | ☐ | |
| OPS01 (GLPI/BookStack) | 24 h | | 24 h | | ☐ | |
| SIEM01 (Wazuh) | 24 h | | 24 h | | ☐ | |
| Workstations (re-image) | 3 days | | n/a | | ☐ | |
| **Full recovery to service** | **per tier** | | | | ☐ | |

Copy the filled table into `business/p08-dr-drill-report.md`.

---

## F. Drill safety (required — read before running a drill in the lab)

- **Snapshot every VM before the drill**, named `snap-p8-ph5-before`.
- Run the drill against **scratch VMs**, not production, unless the point of the exercise is a full
  rehearsal. The sandbox bridge has **no uplink**.
- **Rollback for a restore drill = destroy the scratch environment** (`Remove-VM -Force`, delete the
  disk, delete `/srv/restore-scratch/<host>`). Nothing in production is changed.
- If the drill is a simulated ransomware event, "destroy" the production VMs by **reverting them to a
  snapshot**, never by actually deleting the only copies — the backups are the thing being tested.
- Do **not** shorten Object Lock retention to make a step easier; that defeats the control being tested.
- Record everything with a stopwatch. The first drill should be expected to find problems — a drill
  that finds nothing is usually a drill that was too shallow.

> **Lab practice:** Halden Distribution Ltd. is fictional; the runbook above is the design. Do not claim
> an RTO until a real timed drill has been run and the table above is filled with measured values.
