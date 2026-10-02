# P8 — Phase 0: Design document (design before you build)

**Project:** P8 Backup, Recovery and Disaster Recovery with Automated Restore Verification
**Company:** Halden Distribution Ltd. (fictional, 85 users) · **Domain:** `ad.halden.internal`
**Status:** build kit complete — lab execution pending · **Owner:** Muhammad Ibrahim Akmal · **Mode:** A (Advisor)
**Spec:** [`docs/plan/P08-backup-dr-restore-verification.md`](../../../docs/plan/P08-backup-dr-restore-verification.md)
**Build order:** 6 of 10 (tailored order P1 → P2 → P9 → P3 → P4 → **P8** → P5 → P6 → P7 → P10)

> Why design first: a backup design is really a *business* design. Before choosing a tool you have to
> answer "what would it cost Halden to lose this, and how long can we survive without it?" — and that
> answer belongs to the business, not to IT. Getting RTO/RPO, retention and immutability wrong is
> expensive to unwind once terabytes of unprunable history exist. Documenting the design now also
> produces the interview answers about *why*.

---

## 1. Goal and scope

Make Halden able to survive: a deleted file, a failed server, a corrupted database, and a full
ransomware attack that also destroys the production servers. Concretely:

- A **Business Impact Analysis (BIA)** with every department, producing RTO/RPO per system, signed off.
- A **3-2-1-1-0** backup strategy — 3 copies, 2 media, 1 offsite, 1 immutable/offline, **0 errors on
  verified restore**.
- A **hardened, non-domain-joined backup server** (BKP01) with encrypted repositories.
- **Automated weekly restore verification** that publishes a pass/fail result, not a green tick.
- **AD recovery drills** (Recycle Bin, authoritative restore, documented forest recovery).
- A **DR runbook** and a timed ransomware recovery drill with measured RTO/RPO against target.

**Out of scope:** Microsoft 365 / Entra mailbox backups (licence-bound; rejected in
`00-research-and-selection.md` §38), and continuous replication / HA (a different problem from
backup). The lab itself is never exposed to the internet.

## 2. Business context — what is worth protecting, and what it costs to lose

Halden "has backups": a nightly copy of the file server to a USB disk plugged into the same server,
running under a Domain Admin account. Nobody has ever tried a restore. The domain controllers are
not backed up at all. Nobody knows how long the order system can be down before it costs real money.

That is worse than having nothing, because it creates false confidence. The market evidence is
blunt: attackers target backup repositories in **~96% of ransomware attacks** and succeed in **~76%**
of those attempts (Veeam Ransomware Trends); ransomware appears in **88% of SMB breaches**
(Verizon DBIR 2025). The job ad asks for backup and DR procedures that are **periodically verified**
— and untested backups are the gap auditors and insurers find most often.

**What matters, in business terms:**

| Asset | Business role if lost |
|---|---|
| AD (DC01/DC02) | Nobody can log in to anything. Everything else is unreachable. |
| FS01 Finance / Sales shares | Invoices, orders, payment files — work stops the same hour. |
| LNX01 order system + database | Orders cannot be taken or dispatched; the warehouse stalls. |
| FW01 config | The network perimeter cannot be rebuilt quickly. |
| OPS01 (GLPI, Uptime Kuma) | Service desk and monitoring go dark; you lose sight of the incident. |
| SIEM01 (Wazuh) | You lose the timeline you need to find a clean restore point. |
| Workstations | Inconvenient, not existential — re-imaged from a standard build. |

**Success = the measurable criteria** in the P8 plan (BIA signed off; 3-2-1-1-0 evidenced; immutability
deletion refused; DC backed up and restored; weekly restore test passing to Uptime Kuma; timed DR
drill measured against target; runbook usable by someone else).

## 3. Design principles

1. **The business sets RTO/RPO; IT shows the cost of each option.** A target nobody agreed to is a
   target nobody will fund.
2. **Restore is the product, not backup.** A backup job that "succeeded" proves nothing until a
   restore has been tested. Every claim in this project is a *restore* claim.
3. **Assume the domain is already compromised.** The backup plane must not depend on the thing it is
   protecting, so BKP01 is not domain-joined and uses its own credentials.
4. **Immutability is a property of the destination, not a promise in a policy.** Object Lock, not
   "the backup account is trusted".
5. **One thing off the wire.** At least one copy is offline and physically removed, so no credential
   on the network can reach it.
6. **Evidence first.** Every phase defines what to capture *before* it runs (§15); no measured number
   is written down until it exists.
7. **Snapshot before every phase** (§16); every change gets a rollback note. For a restore drill the
   rollback is "destroy the scratch environment".

## 4. Asset and system tiers (from the BIA)

The BIA interviews produce tiers, not a wish list. This is the tier table the policy is built on
(targets agreed with the business — see `business/p08-service-levels.md`):

| Tier | Systems | RTO | RPO | Backup frequency | Retention |
|---|---|---|---|---|---|
| **0 — Foundation** | DC01/DC02 (AD, DNS, DHCP), FW01 config | 2 h | 24 h (AD changes are rare; replication covers the gap) | Daily VM + daily system state | 30 daily, 12 monthly |
| **1 — Critical** | FS01 Finance/Sales shares, LNX01 order app + database | 4 h | **1 h** | Hourly file incremental; nightly VM | 14 daily, 8 weekly, 12 monthly |
| **2 — Important** | OPS01 (GLPI/BookStack), SIEM01 (Wazuh) | 24 h | 24 h | Nightly | 14 daily, 4 weekly |
| **3 — Deferrable** | Workstations (no local data by policy; folder redirection) | 3 days | n/a | Re-image from the standard build | — |

**Tier 0 vs Tier 1 is a deliberate distinction.** Losing AD means losing *identity* — a much harder
recovery than losing *files*. That is why DCs get both a VM-level backup and a system-state backup
(the system-state copy is what enables an authoritative restore).

## 5. The 3-2-1-1-0 mapping for Halden

| Rule | Halden implementation |
|---|---|
| **3 copies** | (1) production data, (2) on-site repository on BKP01, (3) offsite object store |
| **2 media** | Disk repository on BKP01 **and** S3-compatible object storage (lab MinIO; prod Backblaze B2 / Wasabi); a rotating encrypted USB adds a third medium |
| **1 offsite** | MinIO/cloud bucket outside the LAN; monthly encrypted USB stored off-site |
| **1 immutable / offline** | Object Lock in **COMPLIANCE** mode (30-day default retention) **plus** the disconnected USB |
| **0 errors on verified restore** | The weekly `Test-BackupRestore` run: hash-checked file restores + a sandboxed VM boot with service health checks; a failure is a High alert and a ticket |

## 6. RPO/RTO targets per system

The full table (with the business owner and the review date) is
`configs/p08-rpo-rto-targets.md` and `business/p08-service-levels.md`. The design values above are
**targets**, not results: actual recovery times are pasted in only after the timed drill in
`docs/runbooks/dr-drill-full-recovery.md`. Every row in `README.md` starts as "not measured".

## 7. Backup platform and jobs

**Lab reality.** P1 chose **Hyper-V on Windows 11 Pro** (decision D9), not Proxmox, so the
Proxmox-Backup-Server option in the plan is not the default here. The build kit therefore uses a
**restic-centric core that works on any hypervisor**, with the VM layer handled by the Hyper-V
scripts (`Export-VM` + application-consistent checkpoint) and Windows system state by `wbadmin`.

| Layer | Tool | Where it runs | What it protects |
|---|---|---|---|
| VM-level | `02-Backup-HyperVVMs.ps1` (Hyper-V `Export-VM` after a production/VSS checkpoint) | HOST01 | Whole VMs, per tier → BKP01 |
| File-level | `restic` via `restic backup` (Linux) / `restic.exe --use-fs-snapshot` (Windows) | BKP01 / FS01 | Tier 1/2 shares and application data |
| AD system state | `wbadmin start systemstatebackup` + restricted copy to BKP01 | DC01/DC02 | AD, SYSVOL, registry — enables authoritative restore |
| Offsite | `restic copy` to MinIO S3 | BKP01 | Copy 2, immutable |
| Offline | encrypted USB export | BKP01 (manual, monthly) | Copy 3, air-gapped |

**Drop-in alternatives (documented, not default).** On Proxmox, Proxmox Backup Server replaces the
VM-level layer with dedup, encryption and built-in verify jobs and `01-Configure-BackupRepository.sh
--with-pbs` installs it. On Hyper-V, Veeam Backup & Replication Community Edition with a Linux
Hardened Repository is the commercial-equivalent path. Both are free for this lab; the restic design
is used because it is fully scriptable and hypervisor-agnostic. This deviation is recorded in
`DECISIONS.md`.

## 8. Immutability design

**Object Lock requires bucket versioning** — this is the single most important thing to understand.
When restic (or an attacker with the backup credentials) "deletes" an object, S3 only adds a **delete
marker**: the locked **object versions** stay intact until retention expires. restic operates
normally, `prune` "succeeds" from its own point of view, and storage only shrinks once the locks
expire. Two consequences:

1. **Retention (30 days) must be ≥ the recovery window promised to the business.** You cannot shorten
   it in COMPLIANCE mode — not even as the root user — which is exactly the point.
2. A **lifecycle rule** expires non-current versions *after* the lock period so the bucket does not
   grow forever.

The BIA also drives retention on the local repository (`restic forget --keep-hourly 24 --keep-daily
14 --keep-weekly 8 --keep-monthly 12 --prune`, Tier 1). The immutability proof — `05-Test-Immutability.sh`
— is a first-class deliverable, not a footnote: the evidence is a **failed** deletion.

## 9. Why BKP01 is not domain-joined

A Domain Admin on a domain-joined backup server can delete the backups. If the domain is
compromised — which is the exact scenario backups exist for — a joined backup server is compromised
with it, and it is reached with the same credentials that were just stolen. BKP01 therefore:

- has **its own local credentials**, held in the owner's password manager, with TOTP on the console;
- lives in the **MGMT VLAN 40** (from P6) and is reachable only on the backup ports;
- has **no internet route** except to the offsite target;
- runs a **Wazuh agent** (P7) with an alert on repository deletion attempts;
- uses **separate backup credentials**, never Domain Admin.

The trade-off is real and documented: an unjoined server is one more set of credentials to manage
and cannot use domain SSO. For a backup repository, that isolation is the feature, not a cost.

## 10. Encryption and key escrow

Repositories are encrypted **client-side**: the restic passphrase never reaches the storage provider,
so a bucket compromise still yields only ciphertext. The passphrase and the MinIO keys are read from
an **uncommitted env file** (`/etc/halden-lab/backup.env` on BKP01, template in `configs/backup.env.example`)
and are **never** committed to Git or the website.

**Losing the key means losing the backups.** Escrow is therefore part of the design, not an
afterthought: the passphrase is stored in the owner's password manager **and** in a sealed offline
copy (printed, sealed envelope, stored with the offline USB). Key location is recorded in the DR
runbook. Key **rotation** would require re-initialising the repository and re-running a full backup,
so it is a change-managed event.

## 11. Restore-verification design (the "0" of 3-2-1-1-0)

`06-Test-BackupRestore.sh`, scheduled weekly on BKP01:

1. **File-level** — pick a deterministic-but-rotating sample of 20 files from the latest snapshot
   (`restic ls latest --json`), restore them to `/srv/restore-test/<date>/`, compute SHA-256 and
   compare against the **source hash manifest** written at backup time (falling back to the live
   file's hash where it is unchanged). Then `restic check --read-data-subset=5%` for repository
   integrity.
2. **VM-level** — restore the week's VM (rotating DC01 → FS01 → LNX01 → …) into **sandbox VLAN 99**
   with no uplink, boot it, wait for it to settle, and run a **service health check** (DC: NTDS, DNS,
   Netlogon; FS01: shares reachable; LNX01: the app answers on its port). Then destroy the scratch VM.
3. **Output** — `reports/restore-test-<date>.json`, an HTML summary, a one-line result appended to
   `data/p08-restore-test-history-template.csv`'s real counterpart, and a **push to Uptime Kuma**
   (up = pass; P9 owns the monitor). A failure raises a High alert (P7) and a ticket (P9).
4. **12-week history** is the "periodically verify backups" evidence and feeds the P10 monthly KPI.

The restore-verification gate is the difference between "we run backups" and "we can restore".

## 12. AD recovery design

Three escalating procedures, each with a runbook and a drill:

1. **Deleted object (everyday)** — AD Recycle Bin (`Restore-ADObject`), restoring the OU before its
   children. Fast, online, no downtime.
2. **Authoritative restore (bulk/older mistake)** — boot into **DSRM**, restore system state
   (`wbadmin start systemstaterecovery`), mark the subtree authoritative (`ntdsutil`), reboot, verify
   replication. Only used when Recycle Bin cannot help.
3. **Forest recovery (worst case, tabletop + partial lab)** — isolate, restore **one** DC from a
   known-clean pre-compromise backup into an isolated network, seize FSMO roles, metadata-clean the
   other DCs, reset **krbtgt twice**, reset DC account and trust passwords, authoritative SYSVOL
   (DFSR) restore, rebuild other DCs fresh, reconnect. Timed in the sandbox.

**Tombstone lifetime (180 days):** never restore a DC from a backup older than the tombstone
lifetime, or lingering objects reappear. The design records the backup age on every DC restore.

## 13. DR design and recovery order

`business/p08-dr-plan.md` and `docs/runbooks/dr-drill-full-recovery.md` define the order and the
decision points. The recovery order follows dependencies, not convenience:

```
0. Declare disaster (MD + IT Lead), start IR (P7), preserve evidence, isolate the network
1. Verify clean infrastructure: hypervisor, FW01 config (from Git, P9)
2. BKP01 health check; choose a restore point BEFORE the compromise (SIEM timeline)
3. DC01 restore (sandbox first, scan, then promote) → DNS/DHCP verify
4. Reset krbtgt x2, privileged passwords, LAPS rotation (P3)
5. FS01 restore → share access tested with a Finance user
6. LNX01 order app → functional test with Sales
7. OPS01, SIEM01
8. Re-image workstations from the standard build → users back to work
9. Hand back to the business; lessons-learned review
```

**Decision points** (each with a stated owner): restore in place vs rebuild; restore point selection
when the compromise date is uncertain; whether to bring a restored DC straight to production or scan
it in the sandbox first (always scan first); and when to accept data loss against the RPO.

## 14. Network and VLAN placement

In P1 the lab is flat (`192.168.10.0/24`). P8 keeps BKP01 on the LAN for now and it moves to the
**MGMT VLAN 40** when P6 implements segmentation — exactly as the roadmap requires. The isolation is
a firewall decision (only the backup ports from the hypervisor/agents; no internet except the offsite
target) plus the Wazuh monitoring from P7. The sandbox for restore tests is **VLAN 99**, no uplink.

## 15. Evidence plan (per phase)

| Phase | Deliverable | Evidence to capture |
|---|---|---|
| 0 | BIA, tiers, RTO/RPO signed off | BIA report; signed service-level table |
| 1 | BKP01 hardened; repository + jobs; DC system state | BKP01 hardening (not domain-joined, SSH), job results, `wbadmin` system-state output |
| 2 | Immutable offsite copy | MinIO `mc retention` config; **failed** `mc rm --versions`; `mc retention clear` refused; successful `--rewind` recovery; restic copy log |
| 3 | Weekly restore verification | restore-test JSON + HTML over several weeks; history CSV; Uptime Kuma backup heartbeat |
| 4 | AD recovery drills | Recycle Bin restore; authoritative restore in sandbox; timed forest-recovery steps |
| 5 | DR runbook + timed drill | DR drill timing table; runbook; issues found and fixed |

**Naming** (AGENTS.md 4.5): `p08-phN-<what>-<before|after|result>.<ext>`.

## 16. Snapshot and rollback plan

- **Before every phase:** take a hypervisor snapshot of each VM the phase touches, named
  `snap-p8-ph<N>-before`. Rollback = revert that snapshot and re-run the previous phase's scripts.
- **Restore drills:** the scratch target is a **new, separate VM** (e.g. `RESTORE-TEST` or VM id
  9001). The rollback is to **destroy the scratch VM** (`Remove-VM -Force` and delete its disk); it
  is never attached to the production network. The sandbox bridge has no uplink.
- **DC caution:** restoring or reverting a domain controller is the riskiest operation here. DC
  restores are performed in the sandbox first and only promoted after scanning. Reverting a DC
  snapshot can disturb replication, so it is a last resort and is recorded.
- **BKP01 caution:** deleting a repository is unrecoverable — there is no "undo" for a repository
  prune. Immutability protects Copy 2; the offline USB is the fallback for Copy 1.

## 17. Honest limitations of a home lab

Being explicit here is part of the design, not a disclaimer:

- **MinIO on a lab VM is not a real cloud.** It is a separate VM/disk that simulates object storage,
  including Object Lock, but it shares the same physical host and power. Only the offline USB is
  genuinely independent of the host.
- **Scale.** Halden's data is small (tens of GB, not terabytes), so throughput, dedup ratios and
  storage cost are illustrative, not representative.
- **No UPS.** A host power loss can corrupt a VM mid-backup; the design relies on clean shutdowns and
  the fact that a backup is only trusted after a restore test.
- **Targets vs results.** RTO/RPO here are agreed targets. The value of the project is the
  *measurement framework* and the *verified restore*, both of which are real.
- **Single site.** The lab has no second physical site; "offsite" is a second medium plus a physically
  removed disk.

## 18. Decisions and risks

**Decisions taken** (to be recorded in `DECISIONS.md`): restic-centric core instead of a
hypervisor-specific backup product, with PBS/Veeam documented as drop-in alternatives; BKP01 stays
non-domain-joined and moves to MGMT VLAN 40 in P6; secrets live in an uncommitted env file; MinIO
object storage simulates the offsite provider.

| Risk | Mitigation |
|---|---|
| Backup server joined to the domain it protects | BKP01 not domain-joined; separate credentials; §9 |
| Encryption key stored only on the backup server | Escrow in password manager **and** sealed offline copy; §10 |
| Measuring "backup succeeded" instead of "restore succeeded" | The weekly restore test is the KPI; §11 |
| Restoring a DC older than the tombstone lifetime | Backup-age check on every DC restore; §12 |
| DR runbook stored only on the file server being recovered | Printed copy stored off-site; runbook also in Git; §13 |
| Object Lock retention shorter than the promised window | Retention (30 d) ≥ recovery window; tested; §8 |
| Immutability silently misconfigured (governance vs compliance) | `05-Test-Immutability.sh` proves deletion is refused; §8 |
| Someone deletes the repository during a test | Tests use a scratch target; BKP01 deletion alert via Wazuh (P7); §16 |

## 19. Interview notes (phase 0)

**"Why 3-2-1-1-0 and not just 3-2-1?"** Because attackers specifically target backups: Veeam found
repositories targeted in ~96% of ransomware attacks, succeeding in ~76%. The extra "1" makes a copy
**immutable or offline**, so even with the backup credentials an attacker cannot destroy the history;
the "0" makes **verification** a requirement rather than an assumption.

**"What does immutability actually protect against?"** A compromised backup account and ransomware
that reaches the repository. With S3 Object Lock in COMPLIANCE mode, deletes become delete markers
and the locked versions cannot be removed or their retention shortened — not even by the root user —
until the retention expires. It does **not** protect against a bad restore point, a lost key, or
retention set shorter than the promised recovery window; that is why retention ≥ recovery window.

**"How did you decide RTO/RPO?"** I did not — the business did, through the BIA. I showed each
department the cost of each option (tighter RPO means more frequent backups means more cost), and
they signed off the targets. My job was to make the technical options and their cost legible.

**"A director asks 'can we restore?' — what do you say?"** "I do not trust a green tick. Every week
we restore files, hash-compare them and boot a server in a sandbox, and the result goes to
monitoring; here is the history. And we have run a timed full-recovery drill, so I can give you a
number rather than a promise." If a number has not been measured yet, the honest answer is "not
measured yet — here is the target and the date we will prove it."

---

*Next step: Phase 1 — prepare and harden BKP01, then configure the repository and jobs
(plan §Phase 1). Snapshot first; in Mode A the owner runs the commands and pastes output back.
The measured facts are pasted into `docs/as-built.md` afterwards.*
