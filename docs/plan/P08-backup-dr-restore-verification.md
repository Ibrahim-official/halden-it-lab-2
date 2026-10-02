# P8: Backup, Recovery and Disaster Recovery with Automated Restore Verification

> **Pitch:** Designed and implemented a **3-2-1-1-0** backup strategy (3 copies, 2 media, 1 offsite, 1 immutable/offline, 0 errors on verified restore) driven by a Business Impact Analysis with each department. Added automated weekly restore tests that prove the backups work, an AD recovery drill, and a DR runbook with **measured** RTO/RPO: full ransomware-scenario recovery of core services in **X minutes** against a target of Y.

**Anchor score:** 97 (merged with #36 BIA/DR runbook, #37 AD recovery drill) · **Time:** about 2 weeks · **Depends on:** P1–P7

---

## 1. Business problem

Halden "has backups": a nightly copy of the file server to a USB disk plugged into the same server, running under a Domain Admin account. Nobody has ever tried a restore. There's no backup of the domain controllers, and nobody knows how long the business can survive without the order system.

**Market evidence:**
- Attackers target backup repositories in **~96% of ransomware attacks**, and succeed in **~76%** of those attempts (Veeam Ransomware Trends).
- Ransomware is present in 88% of SMB breaches (Verizon DBIR 2025).
- The job ad asks for backup, recovery and DR procedures that are **periodically verified**. Untested backups are the gap auditors and insurers find most often.

## 2. JD coverage

| Ad | Bullet proven |
|---|---|
| SysAdmin | **Maintain backup, recovery, and disaster-recovery procedures and periodically verify backups** |
| SysAdmin | Maintain backups (listed under endpoint/patching bullet) |
| SysAdmin | Technical documentation; vendor coordination (offsite storage provider) |
| Officer | **Work with different departments** (BIA interviews); understand business operations; prepare reports/presentations |

## 3. Success criteria

- [ ] **BIA** completed with every department: critical processes, MTD, **RTO/RPO per system**, signed off
- [ ] Backup policy mapped to BIA tiers; **3-2-1-1-0** achieved and evidenced
- [ ] **Immutable copy:** a deletion attempt with backup-admin credentials **fails** (tested)
- [ ] DC protection: VM-level + **system state** backups; Recycle Bin (P3) + **authoritative restore** demonstrated
- [ ] **Automated weekly restore test:** random files restored and hash-verified, one VM booted in an isolated network with a service health check, result pushed to Uptime Kuma (P7)
- [ ] **DR drill:** full ransomware scenario rebuild of core services; **measured RTO/RPO vs target**
- [ ] DR runbook usable by someone who isn't you (tested by following it step by step)

## 4. Architecture

```
 Production (VLAN 10/30)                       MGMT VLAN 40 (isolated backup plane)
 ┌───────────────────────┐   nightly    ┌────────────────────────────────────────────┐
 │ DC01 DC02 FS01 LNX01  │ ───────────► │ Copy 1: BKP01 primary repository            │
 │ OPS01 SIEM01          │  VM-level +  │   Option A (Proxmox): Proxmox Backup Server │
 │ WS (user data via FS) │  system state│   Option B (Hyper-V): Veeam B&R Community + │
 └───────────────────────┘  + file-level│     Linux Hardened Repository (immutable)   │
                                         └──────────────┬─────────────────────────────┘
                                            sync/copy   │  restic (file-level, encrypted)
                                                        ▼
                                  Copy 2: MinIO S3 with **Object Lock (compliance mode)**
                                           [lab: separate VM/disk; prod: Backblaze B2 /
                                            Wasabi / S3 with object lock = offsite]
                                                        │ monthly
                                                        ▼
                                  Copy 3: Offline, encrypted USB rotated off-site (air gap)

 Verification: Test-BackupRestore (weekly) → isolated VLAN 99 sandbox → report → Uptime Kuma push
 Backup server: NOT domain-joined, local accounts + MFA/TOTP on console, firewall-restricted
```

## 5. Tools and cost

**Option A:** [Proxmox Backup Server](https://www.proxmox.com/en/proxmox-backup-server) (free; dedup, encryption, verify jobs, sync) · **Option B:** [Veeam Backup & Replication Community Edition](https://www.veeam.com/products/free/backup-recovery.html) (free, up to 10 workloads) · [restic](https://restic.net) · [MinIO](https://min.io) with Object Lock · Windows Server Backup (`wbadmin`) for DC system state · PowerShell/bash. **Cost: free.** Optional real offsite: Backblaze B2 with Object Lock costs very little per month for lab-sized data (billed in USD).

## 6. Step-by-step action plan

### Phase 0: Business Impact Analysis (Day 1–2)
Start with the business side: people, not tools.
1. **Interview each department head** (role-play and write up; use `business/p8-bia-questionnaire.docx`):
   - What are your critical processes? (e.g. Sales: order entry; Finance: payroll, supplier payments; Ops: dispatch/picking; HR: onboarding)
   - What's the impact after 1h / 4h / 1 day / 3 days down? (financial, customer, legal, reputational)
   - What's the **maximum tolerable downtime (MTD)**? How much data could you re-enter (**RPO**)?
   - What systems, files and people does the process depend on? Any manual workaround?
   - Peak periods (month-end, payroll day)?
2. **Consolidate into system tiers:**

   | Tier | Systems | RTO | RPO | Backup frequency | Retention |
   |---|---|---|---|---|---|
   | 0 – Foundation | DC01/DC02 (AD, DNS, DHCP), FW01 config | 2 h | 24 h (AD changes are rare; replication covers it) | Daily VM + daily system state | 30 daily, 12 monthly |
   | 1 – Critical | FS01 Finance/Sales shares, order system (LNX01 app + DB) | 4 h | **1 h** | Hourly file snapshots/incremental; nightly VM | 14 daily, 8 weekly, 12 monthly |
   | 2 – Important | OPS01 (GLPI/BookStack), SIEM01 | 24 h | 24 h | Nightly | 14 daily, 4 weekly |
   | 3 – Deferrable | Workstations (no local data by policy; OneDrive/FS redirect) | 3 days | n/a | Re-image | — |
3. **Management sign-off** on the targets, and on the **cost/risk trade-off** (tighter RPO = more cost). **This is exactly the "understand business operations / work across departments" part of the Officer ad.**

### Phase 1: Backup policy and secure backup platform (Day 3–4)
1. Write `business/p8-backup-policy.md`: scope, tiers, 3-2-1-1-0, retention, encryption, roles, monitoring, **verification schedule**, and the rule that backup credentials are separate from domain credentials.
2. **Harden BKP01 before storing anything** (this is where most SMBs fail):
   - **Not domain-joined.** If AD is compromised, the backups aren't.
   - Local admin with a unique password (password manager) + **TOTP 2FA** on the PBS/Veeam console
   - Lives in the MGMT VLAN. Firewall allows only the backup ports from the hypervisor/agents; no internet except the offsite target
   - Full-disk encryption; backup data **encrypted client-side** (keys stored offline in a sealed envelope/password manager. **Losing the key means losing the backups**, so document key escrow)
   - Wazuh agent (P7) + an alert on repository deletion attempts
3. **Option A (Proxmox):** install PBS on BKP01, create a datastore, add it to the Proxmox VE host as storage. Backup jobs per tier with `mode snapshot` + qemu-guest-agent (filesystem freeze). Enable **encryption**, a **verify job** (weekly, re-verify after 30 days), a **prune/GC schedule**, and **remove-vanished**.
   **Option B (Hyper-V):** install Veeam CE on a Windows mgmt box (not domain-joined). Add BKP01 as a **Linux Hardened Repository** (XFS with reflink, single-use credentials, immutability 14 days). Jobs with **application-aware processing** for DCs.
4. **DC system state** (belt and braces, and it enables authoritative restore):
   ```powershell
   # On DC01 (Windows Server Backup feature), to a dedicated volume/share only BKP can read
   wbadmin start systemstatebackup -backupTarget:E: -quiet
   ```
   Schedule daily. Copy the output to BKP01 via a restricted account. Keep in mind the **tombstone lifetime (180 days)**: never restore a DC backup older than that.

### Phase 2: Immutable offsite copy with restic + MinIO Object Lock (Day 5–6)
1. MinIO on a separate VM/disk (simulating a cloud provider), create a bucket **with Object Lock enabled at creation** and a default retention of **COMPLIANCE 30 days**:
   ```bash
   mc mb --with-lock halden/backup-immutable
   mc retention set --default COMPLIANCE 30d halden/backup-immutable
   ```
2. restic from FS01 (file-level, Tier 1 shares) and from the PBS/Veeam export:
   ```bash
   export RESTIC_REPOSITORY=s3:https://minio.halden.internal/backup-immutable/fs01
   export RESTIC_PASSWORD_FILE=/root/.restic-pass     # escrowed offline
   restic init
   restic backup /mnt/fs01/Finance /mnt/fs01/Sales --tag tier1 --exclude-caches
   restic forget --keep-hourly 24 --keep-daily 14 --keep-weekly 8 --keep-monthly 12 --prune
   ```
   On Windows, use `restic.exe` with VSS (`--use-fs-snapshot`) as a scheduled task under a dedicated backup service account (gMSA where possible).
   **How Object Lock works with restic (know this for interviews):** Object Lock requires bucket **versioning**. When restic (or an attacker) "deletes" a file, S3 only adds a *delete marker*. The locked **object versions** stay intact until retention expires. restic works normally, `prune` "succeeds" from its point of view, and storage only shrinks once locks expire. So retention (30d) must be ≥ the recovery window you promise the business. Add a bucket lifecycle rule to expire noncurrent versions after the lock period.
3. **Immutability test (key evidence):** with the backup user's credentials:
   - `mc rm --recursive --force halden/backup-immutable/fs01` → "succeeds" but only adds delete markers
   - `mc rm --recursive --force --versions halden/backup-immutable/fs01` → **must fail** (object is WORM-protected)
   - `mc retention clear` / shortening retention in COMPLIANCE mode → **must fail**, even for the root user
   - **Recover** the "deleted" repo as of before the attack: `mc cp --recursive --rewind 1h halden/backup-immutable/fs01 /restore/fs01-repo/`, then `restic -r /restore/fs01-repo snapshots`
   Screenshot the failures and the successful rewind. This proves an attacker with backup credentials still can't destroy your history.
4. **Offline copy:** a monthly script exports the latest PBS/Veeam backup + restic repo to an encrypted USB (VeraCrypt/LUKS), then "disconnect and store off-site". Document the rotation log.

### Phase 3: Automated restore verification, the "0 errors" (Day 7–9)
`scripts/Test-BackupRestore.ps1` (or `.sh`), scheduled weekly:
1. **File-level test:**
   - Pick 20 random files from the restic snapshot list (`restic ls latest --json`)
   - Restore to `/restore-test/<date>/`, compute SHA256, compare to the **source hash manifest** (written at backup time by a pre-backup script) or the live file's hash if unchanged
   - `restic check --read-data-subset=5%` for repository integrity
2. **VM-level test** (Proxmox example):
   ```bash
   qmrestore <pbs-backup-id> 9001 --storage local-lvm --unique 1
   qm set 9001 --net0 virtio,bridge=vmbr99          # isolated sandbox bridge, no uplink
   qm start 9001 && sleep 180
   qm guest exec 9001 -- powershell -c "Get-Service NTDS,DNS,Netlogon | ? Status -ne 'Running'"   # DC health
   qm stop 9001 && qm destroy 9001 --purge
   ```
   Rotate which VM is tested each week (DC → FS01 → LNX01 → …). For FS01, check shares; for LNX01, check that the app responds on its port.
3. **Output:** `reports/restore-test-<date>.json` (files tested, hashes matched, VM booted, service checks, **measured restore duration**), an HTML summary, and a **push to Uptime Kuma** (up = pass). A failure raises a High alert (P7) and a ticket (P9).
4. Keep a 12-week history. This is the "periodically verify backups" evidence and feeds P10's monthly KPI ("restore test success rate: 12/12").

### Phase 4: Active Directory recovery drills (Day 10)
1. **Deleted object (everyday):** delete `OU=Sales` (turn off accidental-deletion protection first, in the lab) → restore with AD Recycle Bin:
   ```powershell
   Get-ADObject -Filter 'isDeleted -eq $true -and Name -like "*Sales*"' -IncludeDeletedObjects |
     Restore-ADObject          # restore OU first, then its children
   ```
2. **Authoritative restore (older or bulk change):** boot DC02 into **DSRM**, restore system state (`wbadmin start systemstaterecovery`), then `ntdsutil "authoritative restore" "restore subtree OU=Sales,..." q q`, reboot, verify replication.
3. **Worst case, forest recovery (tabletop + partial lab):** document the Microsoft forest-recovery sequence: isolate → restore **one** DC from a known-clean backup (pre-compromise date) into an isolated network → seize FSMO roles → metadata-clean the other DCs → reset **krbtgt twice**, reset the DC computer account and trust passwords → authoritative SYSVOL (DFSR) restore → rebuild other DCs fresh → reconnect. Run steps 1–4 in the sandbox VLAN and time them.

### Phase 5: DR runbook and full ransomware drill (Day 11–13)
1. `docs/dr/dr-runbook.md`: **decision tree** (what happened → which procedure), **recovery order with dependencies**, and step-by-step procedures with expected outcomes:
   ```
   0. Declare disaster (who: MD + IT Lead), start IR (P7), preserve evidence, isolate network
   1. Clean build/verify infrastructure: hypervisor, FW01 (config from Git, P9)
   2. BKP01 health check; choose restore point BEFORE compromise (use SIEM timeline)
   3. DC01 restore (sandbox first; scan; then promote to prod network) → DNS/DHCP verify
   4. Reset krbtgt x2, privileged passwords, LAPS rotation (Reset-LapsPassword)
   5. FS01 restore → share access test with a Finance user
   6. LNX01 order app → functional test with Sales
   7. OPS01, SIEM01
   8. Re-image workstations (standard build) → users back to work
   9. Hand back to business; lessons learned
   ```
   Include the **contact list** (P7), vendor support numbers, licence keys location, the **encryption key escrow** location, and a **printed copy** (the wiki may be down during a disaster).
2. **Drill:** snapshot everything, then simulate ransomware (delete/encrypt the lab VMs' disks or roll them to a "destroyed" state). **Follow the runbook exactly**, with a stopwatch. Record:
   | System | RTO target | Actual | RPO target | Actual data loss | Pass? | Notes / fix |
   |---|---|---|---|---|---|---|
3. Fix whatever the drill exposed (you'll find something: a missing driver, a forgotten password, a wrong order) and update the runbook. **The drill report with "what broke" is more impressive than a perfect result.**

## 7. Business layer (IT Support Officer)

| Artifact | Purpose |
|---|---|
| `business/p8-bia-report.pdf` | Department impact findings, tiers, RTO/RPO signed off |
| `business/p8-backup-policy.md` | Policy (links to P10 policy pack) |
| `business/p8-dr-drill-report.md` | Results vs targets, issues, actions with owners/dates |
| `business/p8-management-brief.pptx` (5 slides) | "Can we survive ransomware?" Before: untested USB backups. After: immutable, verified, measured recovery. Residual risks and budget asks (e.g. a real offsite subscription) |

## 8. Evidence to capture

BIA tier table · BKP01 hardening (not domain-joined, 2FA) · job history · PBS/Veeam verify job success · **failed deletion on immutable bucket** · restore test JSON/HTML over several weeks · Uptime Kuma backup heartbeat · Recycle Bin restore + authoritative restore · DR drill timing table · runbook.

## 9. Common pitfalls

- Backup server joined to the domain it protects, using Domain Admin credentials. It gets encrypted along with everything else.
- Encryption keys stored only on the backup server.
- Measuring "backup succeeded" instead of "restore succeeded".
- Restoring a DC from a snapshot/backup older than the tombstone lifetime, or restoring a compromised DC to production without scanning.
- A DR runbook stored only on the file server that's being recovered.

## 10. Resume bullets (templates)

- Led a **Business Impact Analysis** with 5 departments to define RTO/RPO per system, then implemented a **3-2-1-1-0 backup strategy** with an isolated, non-domain-joined backup server and an **immutable (S3 Object Lock) offsite copy** that resisted deletion with admin credentials.
- Automated **weekly restore verification** (hash-checked file restores + sandboxed VM boot with service health checks), reaching a **100% restore success rate over N consecutive weeks**, with results fed into monitoring.
- Wrote a **DR runbook** and ran a full ransomware recovery drill, restoring AD, file services and a line-of-business app in **X minutes vs a Y-hour RTO**. Demonstrated AD Recycle Bin and authoritative restores.

## 11. Interview talking points

- **"How do you know your backups work?"** "I don't trust a green tick. I restore every week automatically, hash-compare files, boot VMs in a sandbox, and alert on failure. Here's 12 weeks of results."
- **"Ransomware hit and the backups are encrypted too."** Explain why that can't happen here: immutable copy, non-domain-joined server, separate credentials, offline copy.
- **"How did you decide RTO/RPO?"** "I didn't. The business did, through the BIA. I showed them the cost of each option."

## 12. AI-ready build prompt

```text
Act as a senior backup & disaster recovery engineer mentoring me through a homelab capstone.
Project: P8 Backup, Recovery & DR with Automated Restore Verification, fictional "Halden Distribution Ltd".
Lab: [Proxmox VE -> Option A: Proxmox Backup Server | Hyper-V -> Option B: Veeam B&R Community + Linux Hardened Repo],
ad.halden.internal (DC01, DC02), FS01 (Finance/Sales shares), LNX01 (order app), OPS01, SIEM01 (Wazuh),
Uptime Kuma on OPS01, MGMT VLAN 40, sandbox VLAN 99 with no uplink.

Phase by phase:
0. BIA: department questionnaire, interview notes template, tier table with RTO/RPO, sign-off.
1. Backup policy (3-2-1-1-0) + BKP01 hardening (not domain-joined, 2FA, encryption with key escrow) + backup jobs
   per tier + DC system state with wbadmin (tombstone lifetime considerations).
2. MinIO with Object Lock (COMPLIANCE) + restic (Linux and Windows with VSS), retention, immutability deletion test,
   offline USB rotation procedure.
3. Test-BackupRestore script: random file restore + SHA256 manifest compare, restic check, sandboxed VM restore/boot
   with service checks, rotation schedule, JSON/HTML report, Uptime Kuma push, alert on failure.
4. AD recovery: Recycle Bin restore, DSRM authoritative restore with ntdsutil, forest recovery sequence in sandbox.
5. DR runbook with recovery order and a timed ransomware drill + results table + runbook fixes.
Each phase: commands, expected output, verification, screenshots, pitfalls. Finish with README, drill report,
5-slide management brief outline and resume bullets with my numbers. Start with Phase 0.
```
