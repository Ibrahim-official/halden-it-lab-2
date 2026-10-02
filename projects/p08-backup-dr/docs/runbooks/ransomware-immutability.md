# Runbook — Ransomware: immutability, recovery point selection, and recovery

**Duty:** IT Lead + Systems (with the MD informed) · **Severity:** Critical · **Applies to:** the whole lab
**Audience:** the incident team. Defensive content only: what to check and how to recover — not an
attack guide.

## 0. First 15 minutes — contain, do not clean

| Step | Action | Why |
|---|---|---|
| 1 | Declare the incident; inform the Managing Director; start the IR process (P7) | Decisions about restore points and downtime are business decisions |
| 2 | **Isolate, do not power off.** Disconnect the network (or move to VLAN 99 with no uplink); leave the machines running | Powering off loses memory evidence and can trip encryption |
| 3 | Preserve evidence: image affected systems before cleaning, keep logs, note the first symptom and time | You need a timeline to find a clean restore point |
| 4 | Confirm the backups are intact **before** anything else | The whole recovery depends on it |
| 5 | Treat the immutable copy as the source of truth; change all backup credentials | Assume the attacker has the old ones |

## 1. Confirm the backups are intact

On BKP01:

```bash
source /etc/halden-lab/backup.env
restic snapshots --last                # on-site repository still lists snapshots?
restic -r "$OFFSITE_REPOSITORY" snapshots --last   # offsite copies still present?
```

If a repository looks tampered with, treat it as compromised and recover from the other copy.

## 2. Prove the immutable copy cannot be destroyed (this is the design's purpose)

With the **backup user's own credentials** (not root), try to delete the repository:

```bash
# 1. This may "succeed" but only writes delete markers:
mc rm --recursive --force halden/backup-immutable/fs01

# 2. This MUST fail — the object versions are WORM-protected:
mc rm --recursive --force --versions halden/backup-immutable/fs01
#    expected: an error such as "Object is WORM protected and cannot be overwritten"

# 3. Shortening or clearing retention MUST fail, even as root, in COMPLIANCE mode:
mc retention clear --recursive halden/backup-immutable/fs01
mc retention set --default GOVERNANCE 1d halden/backup-immutable/fs01
```

A **failure is the evidence that the design works**. Save the exact error text.

## 3. Choose a restore point BEFORE the compromise

1. Build the timeline from SIEM01 (Wazuh, P7): first suspicious event, first encryption, first
   privilege change.
2. Pick the newest snapshot that is **older than the first suspicious event**, not the newest
   available. When in doubt, pick older.
3. For a domain controller, this is where **krbtgt** and privileged-password resets join the plan
   (§5): assume every credential in the compromised window is burned.

## 4. Recover the "deleted" offsite repository (if it was attacked)

Because Object Lock keeps versions, the repository can be rewound to before the attack:

```bash
mc cp --recursive --rewind 1h halden/backup-immutable/fs01 /srv/restore-scratch/fs01-repo/
restic -r /srv/restore-scratch/fs01-repo/ snapshots        # repository is intact
```

Point a restic restore at that repository and restore the chosen snapshot into the sandbox.

## 5. Recover, in dependency order

Follow `dr-drill-full-recovery.md` §3. The security-specific additions to a normal restore:

1. Restore **one** DC from a known-clean pre-compromise backup, into the sandbox; scan it before it
   touches the production network.
2. **Reset krbtgt twice** (the standard two-reset procedure with a replication cycle between them) and
   reset privileged account, service account and LAPS passwords.
3. Reset the DC computer account password and trust passwords if trusts exist.
4. Authoritative SYSVOL (DFSR) restore if SYSVOL was altered.
5. Rebuild the other DCs fresh from the restored, reset domain rather than restoring them too.
6. Only then bring back file services, the order system and the rest.

## 6. After recovery

- Keep the immutable bucket locked; do **not** shorten retention during the incident — you may need to
  rewind again.
- Rotate all backup credentials and the repository passphrase is **not** rotated during the incident
  unless it was exposed (rotating it mid-incident can lock you out of your own copies).
- Write the incident report (P7 template): timeline, restore points used, recovery time vs RTO,
  data loss vs RPO, what broke, and one prevention action each with an owner and a date.
- Feed the outcome into the monthly KPI report (P10) and update this runbook from what you learned.

## 7. The three failures this design prevents

1. **"The backups were encrypted too."** Copy 1 is unjoined and separate; Copy 2 is immutable in
   COMPLIANCE mode; Copy 3 is offline.
2. **"We restored, but the image was already compromised."** Restore-point selection uses the SIEM
   timeline and a sandbox scan before promotion.
3. **"We didn't know if the backups worked."** The weekly restore test proved it before the attack.

> **Lab practice:** the deletion attempts in §2 are performed **only** against the lab's own MinIO
> bucket, to prove the control. Never run them against any external or employer system (AGENTS.md R1/R6).
