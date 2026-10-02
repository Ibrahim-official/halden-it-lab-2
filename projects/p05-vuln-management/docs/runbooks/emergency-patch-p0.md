# Runbook — Emergency patch (out-of-band) for a P0

**Applies to:** a P0 finding — a known-exploited vulnerability (CISA KEV) on an internet-exposed
asset · **Duty:** IT / Systems, notifying the business immediately · **Target:** fixed within 3 days
**Change path:** emergency change; the change record is raised *during* the work, not before it.

## Why this runbook exists

Normal change control exists so that changes are tested before they reach production. A P0 is the
case where waiting for the next change window is the bigger risk — a flaw that is being exploited in
the wild against a host an attacker can reach. So the order is inverted: **stabilise first, document
immediately after**, and never skip the compromise check.

## 0. First 60 seconds

| Question | Answer it with |
|---|---|
| Which host, which service, which CVE? | `05-prioritize.py explain --cve ... --host ...` |
| Is the asset actually exposed? | Firewall rules; is the service published through FW01? |
| Who owns the asset and who approves downtime? | The owner column in the work list / asset inventory |
| Is the vendor fix available today? | Vendor advisory (PSIRT feed) — is there a fixed version, or only a workaround? |

Tell the IT manager and the asset owner now. A P0 is not a solo decision.

## 1. Containment if the fix will take time

If a fixed version is not available within hours, reduce exposure while you wait:

- Restrict the port at FW01 to the minimum source addresses (VPN or management only).
- Disable the vulnerable feature or protocol if the service can run without it.
- Put the host behind the segmentation rule that blocks the path (P6 rule matrix).

Containment is a **compensating control**, and it is recorded — it does not replace the patch.

## 2. Check for compromise before patching

Do this **first**, because patching over a compromise hides it. See
`docs/runbooks/triage-critical-finding.md` §3 for the detail. Summary:

1. Review authentication and error logs since the vulnerability was published.
2. Look for new accounts, scheduled tasks, services and outbound connections.
3. Compare the running config to the last known-good backup.
4. Preserve evidence (copy logs off the host) before you change anything.

If there are signs of compromise: **stop, treat it as an incident** (P7 runbook), do not patch until
the incident lead says so.

## 3. Apply the fix (with a snapshot)

1. **Snapshot the host** (`snap-p5-p0-<host>-before`). For a VM this is seconds and it is your
   rollback for a botched emergency patch.
2. For an **edge device (FW01)**: back up the configuration first, apply the firmware update, verify
   the rule base and VPN, and keep the backup as the rollback.
   ```bash
   # OPNsense: System -> Configuration -> Backups -> Download configuration (before the update)
   # then System -> Firmware -> Updates, and re-check Interfaces/VPN/Rules after reboot.
   ```
3. For **Windows**: install the specific security update, then verify the service state and, on a DC,
   replication and `dcdiag`.
4. For **Linux**: apply the package upgrade for the affected component, then restart only the
   affected service if a reboot is avoidable.
5. Re-check that the exposed path is closed:
   ```bash
   # from a client, the port that was exposed should now refuse or be filtered
   nc -vz <host> <port>
   ```

## 4. Raise the change record and the ticket note

Use `business/p05-change-record.md`. An emergency change still gets:

- what changed and why, with the CVE and the KEV reference;
- the window it was done in and who approved the downtime;
- the test performed and the result;
- the backout plan (the snapshot / the config backup);
- the verification scan that will prove the fix.

## 5. Verify and close

```bash
./scripts/07-verify-closure.sh --before <before.csv> --after <after.csv> \
  --out evidence/public/p05-verify-closure-result.csv
```

The ticket closes only when the rescan no longer reports the finding. Record the time from
first-seen to closed — that is the MTTR datapoint, derived from the two work lists rather than
estimated.

## 6. Afterwards

- Post-implementation note: what happened, how fast, what it cost, what would have gone wrong if the
  ring design had been skipped.
- If the P0 was avoidable by routine patching, say so honestly in the monthly report: the point of
  the emergency path is that it should be rare.
- Add the vendor advisory to `business/p05-vendor-advisory-log.md` so the next one is expected.

> **Lab practice:** this runbook is written for the isolated lab, where "internet-exposed" is a design
> property. It must not be used against anything outside the lab. Do not claim a 72-hour SLA was met
> until a P0 has actually been remediated and verified in the lab.
