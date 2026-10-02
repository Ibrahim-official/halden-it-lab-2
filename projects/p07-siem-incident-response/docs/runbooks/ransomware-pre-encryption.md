# Runbook — Ransomware / pre-encryption alert

**Applies to:** any host, especially FS01 · **Severity:** SEV1 · **Owner:** Incident Lead
**Detections covered:** D7 (100107 shadow-copy deletion), D5 (100104 LSASS access), D6 (100106
encoded/cradle PowerShell), D9 (100109 new service), D13 (100114 Defender/ASR block).
**Target:** stop the encryption before it starts. This is the alert you drop everything for.

Why this matters: ransomware appears in **88% of SMB breaches** (Verizon DBIR 2025, cited in
`docs/plan/00-research-and-selection.md`), and it spends time escalating privilege before it
encrypts. D7 in particular is the last step before encryption — by the time shadow copies are being
deleted, the clock is at seconds, not hours.

## 0. Treat as SEV1. Now.

Declare the incident, page the Incident Lead, and start the timeline. Do not "investigate first and
escalate later"; the escalation *is* the first step.

## 1. First actions (in this order)

1. **Isolate, do not power off.** Cut the host from the network (VLAN/port) so encryption cannot
   spread and the attacker cannot reach more shares. Powering off loses running-memory evidence.
2. **Protect the shares**: if the file server is implicated, stop new writes if you can do it without
   data loss, and confirm the backup repository (BKP01, P8) is **not** reachable from the affected
   host. Attackers go after backups in almost every ransomware attack — check they cannot reach them.
3. **Check for the backup heartbeat**: is the Uptime Kuma backup monitor green? A failed backup in
   the same window is a very bad sign and changes the recovery plan.
4. **Scope**: query Wazuh for the same host and account across the last 24-48 hours — D1, D5, D6,
   D9, D9b, D11 — to find how far the attacker got.

## 2. What the detections tell you

| Alert | Meaning | Action |
|---|---|---|
| D7 shadow-copy deletion | Encryption likely imminent | Highest priority; isolate immediately, preserve memory |
| D5 LSASS access | Credentials being stolen | Assume the attacker has valid credentials; disable affected accounts after preserving evidence |
| D6 encoded/cradle PowerShell | Delivery/execution stage | Identify the parent process and the payload; do not run it to "see what it does" |
| D9/D9b new service/task | Persistence | Record the service/task before removing it |
| D13 Defender/ASR block | A prevention happened | Good, but repeated blocks mean the attacker is still trying — keep going |

## 3. Containment

- Isolate affected hosts; segment the file shares.
- Disable (not delete) affected accounts once evidence is preserved.
- Block the command-and-control destination at FW01/FW02 if one is identified.
- **Do not pay, and do not promise anything to the business yet** — that is a management decision
  documented in the IR plan (`business/p07-ir-plan.md`).

## 4. Evidence to preserve before any cleanup

- Memory image if you can (this is the one case where it is worth the effort).
- The full alert set for the host, exported and sanitized later.
- The suspicious binaries/service definitions, copied out, not run.
- The Uptime Kuma backup status and the last good backup's timestamp.

## 5. Eradicate and recover

- Identify the entry point (phishing, exposed service, credential abuse) and close it before
  restoring anything — otherwise you restore into a re-infection.
- Rebuild the affected hosts from a known-good image rather than cleaning in place if the root cause
  is not certain.
- Restore data from the **verified** backup (P8) and confirm integrity against the last good backup.
- Re-enable services gradually and watch the SIEM for the same detections returning.

## 6. Aftermath

- Full incident report with a timeline and the root cause.
- Post-incident review within a week; actions tracked in P10.
- Update this runbook and the detection tuning log with what actually happened.

## Rollback

Isolation is reversed by returning the host to its VLAN once it is rebuilt and verified. Account
disables are reversed after reset. Data restoration is from backup; the affected host's pre-incident
snapshot is **not** a safe restore point if the compromise predates it.

> **Honest framing:** steps 1-3 are the defensive response to a detection — what to do when the alert
> fires. The project does not document how to perform an attack; any simulation of these behaviours
> was an authorised, snapshotted lab exercise (`scripts/07`, with approval per AGENTS.md R6).
