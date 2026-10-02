# Runbook — Apply a firewall rule change safely (with rollback)

**Applies to:** FW01 (and FW02 for the tunnel) · **Time:** 15 minutes · **Owner:** IT
**Risk:** High — this is the change that can break everything at once. The backout plan matters more
than the change.

## Why this runbook exists

A firewall rule change has a larger blast radius than almost anything else in this environment: a
mistake can stop authentication, stop Group Policy, stop file access, or lock you out of the firewall
itself. The process below is the difference between "we changed the firewall" and "we changed the
firewall in a documented way, verified by a test, and we can reverse it in ten minutes".

## Before you touch anything

1. **Get the approval.** A rule change needs a reason, an owner and, for anything that widens access,
   a sign-off. The change goes through the change record
   ([`../../business/p06-change-record.md`](../../business/p06-change-record.md)).
2. **Write the rule in the matrix first.** Add the row to
   [`../../configs/p06-zone-rule-matrix.csv`](../../configs/p06-zone-rule-matrix.csv) with its number,
   owner and justification. If you cannot write the justification, you do not have a rule — you have
   a wish.
3. **Snapshot FW01** (`snap-p6-ph<N>-before`) at the hypervisor.
4. **Export the configuration.** This is the real backout:
   ```bash
   ./scripts/12-Export-ConfigBackup.sh --host fw01
   ```
   The export lands in `evidence/raw/` (git-ignored). Note the date in the change record.
5. **Open the FW01 console** in the hypervisor and leave it open. A firewall you cannot reach is an
   outage, not a change.
6. **Confirm the anti-lockout path.** You must still be able to reach the web UI from the MGMT zone.
   If you are changing the MGMT rules, work from the console, not the web UI.

## Making the change

7. **Preview it.** Script 01 runs dry by default and prints each rule in order:
   ```bash
   ./scripts/01-Apply-OpnsenseNetworks.sh --phase rules       # dry-run: prints, changes nothing
   ```
   Check the order. OPNsense evaluates top-down with **first match wins**, so a deny above an allow
   silently breaks the allow.
8. **Apply it** (only after the preview looks right):
   ```bash
   ./scripts/01-Apply-OpnsenseNetworks.sh --phase rules --apply
   ```
   Every rule carries its matrix number in the description, so a firewall log line points straight
   back to its justification.
9. **Watch the deny log for two minutes** after applying. Expected denies are informational;
   unexpected denies from a workstation usually mean an AD port is missing.

## Proving it (never skip this)

10. **Run the affected zone's tests.** From a host in the zone you changed:
    ```bash
    sudo ./scripts/09-Test-Segmentation.sh --zone USERS-HQ
    ```
    A rule change is not complete until the suite still reports what the matrix says it should.
11. **For a USERS-HQ change, always check Group Policy** — a missing RPC port looks like a DNS fault:
    ```powershell
    gpupdate /force ; gpresult /h "$env:TEMP\gp.html"
    ```
12. **Record the result** in `docs/as-built.md` and in the change record.

## Rollback

| Situation | Action |
|---|---|
| A rule is wrong but you can still reach FW01 | Delete or disable that rule in the GUI or through script 01, then re-run step 10 |
| You cannot reach FW01 at all | Restore console access, then `System > Configuration > Backups > Restore` the export from step 4. All rules return to their previous state |
| The change broke a service and you need the previous state immediately | Same as above: restore the configuration export. It is the whole firewall configuration, not just one rule |
| The change looks fine but a service is still broken | Check the deny log first, then `nltest`/`gpresult`, before changing another rule |

## After the change

13. **Update the diagram** if a zone, subnet or flow changed.
14. **Tell the people affected** (the comms plan in the change record).
15. **Add the rule to the quarterly rule review** — the review exists to catch rules that were added
    "temporarily" and never removed.
