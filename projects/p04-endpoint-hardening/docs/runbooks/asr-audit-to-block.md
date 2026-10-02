# Runbook — Move an ASR rule from audit to block (and roll it back)

**Applies to:** WS01/WS02 (pilot), then the Workstations OU · **Time:** 20 minutes (plus the 7-day review)
**Owner:** IT / Systems · **Change:** CHG-2026-004 · **Rollback time:** under 5 minutes

> This runbook is the difference between "we deployed ASR rules" and "we deployed ASR rules without
> breaking the month-end close". Never move a rule to Block without the audit evidence in front of you.

## 0. Preconditions

- [ ] The rule has been in **Audit** mode for **at least 7 days** (`02-Set-AsrAudit.ps1` was run).
- [ ] Event ID **1122** (audited) has been reviewed for that rule on the pilot client.
- [ ] A deliberate test trigger has been run once, so you know the rule actually fires (an EICAR test
      file, or a Microsoft ASR test document where the rule is document-based).
- [ ] The client has a snapshot from before the change: `snap-p4-ph2b-before`.
- [ ] `business/p04-asr-exceptions.md` has a row ready if the answer is "keep it in audit".

## 1. Review the audit events

On the pilot client, in Event Viewer → `Applications and Services Logs → Microsoft → Windows →
Windows Defender → Operational`, filter on:

| Event ID | Meaning |
|---|---|
| **1122** | The rule was **audited**: it would have blocked this action, and allowed it |
| **1121** | The rule **blocked** an action |
| **5007** | Defender configuration changed (useful when someone edits a rule by hand) |

For each event note the **rule ID**, the triggering process and the affected user. A rule with zero
events over 7 days is not proven to be harmless; it is unproven in both directions. The one rule in
this set that needs a real decision is the PSExec/WMI rule — check whether any management tooling on
the client uses it.

You can also pull the events into a CSV for the record:

```powershell
Get-WinEvent -LogName 'Microsoft-Windows-Windows Defender/Operational' |
  Where-Object { $_.Id -in 1121, 1122 } |
  Select-Object TimeCreated, Id, @{n = 'Message'; e = { $_.Message -replace '\s+', ' ' }} |
  Export-Csv C:\Temp\p04-ph2-asr-events.csv -NoTypeInformation
```

Keep the export in `evidence/raw/`, and a **sanitized** excerpt in `evidence/public/`.

## 2. Decide, rule by rule

| Decision | When | What you do |
|---|---|---|
| **Block** | No legitimate event, or events only from untrusted/test processes | Leave it in the blocking set |
| **Keep in audit** | The rule conflicts with business tooling (for example the PSExec/WMI rule with remote management) | Pass the rule in `-KeepAudit` and add a row to the exceptions register |
| **Exclusion** | A named application is falsely flagged, and blocking it stops work | Add a **narrow** path or process exclusion with an approval ticket; never exclude a whole drive |

An exclusion is a decision with a risk attached. It needs a row in the exceptions register with an
owner and an expiry — not a quiet `Add-MpPreference` on one machine.

## 3. Move the approved rules to Block

```powershell
.\scripts\03-Set-AsrBlock.ps1 `
  -ComputerName WS01 `
  -ReviewedAuditDays 8 `
  -WhatIf
```

Review the `-WhatIf` output, then run it for real. If a rule must stay in audit, add it explicitly:

```powershell
.\scripts\03-Set-AsrBlock.ps1 -ComputerName WS01 -ReviewedAuditDays 8 `
  -KeepAudit d1e49aac-8f56-4280-b9ba-993a6d77406c      # PSExec/WMI — reviewed, kept in audit
```

The script refuses to run with fewer than 7 reviewed days unless you pass `-Force`; if you ever do
that, the reason goes in the change record.

**Expected:** the script reports `N rule(s) set to Block` and writes
`p04-ph2-asr-block-result-<timestamp>.csv` containing the blocking count and the exclusion list.

## 4. Confirm the block really happened

Run the same test trigger as before. It should now be **stopped**, and event **1121** (blocked)
should appear rather than 1122. A rule that is configured but never produces a 1121 has not been
proven to work.

```powershell
.\scripts\06-Get-EndpointCompliance.ps1 -ComputerName WS01     # check C4 (ASR) now passes
```

## 5. Rollback (the reason this runbook exists)

If a rule breaks a business task after it starts blocking:

```powershell
# put one rule back into audit
.\scripts\03-Set-AsrBlock.ps1 -ComputerName WS01 -RevertToAudit -RuleId d4f940ab-401b-4efc-aadc-ad5f3c50688a

# or put the whole set back into audit if the impact is unclear
.\scripts\02-Set-AsrAudit.ps1 -ComputerName WS01
```

Then: tell the affected user the block is lifted, open a ticket for the exception, decide between an
exclusion and a different control, and record the decision. **Do not leave a rule in audit mode
forever by accident** — the compliance report counts audit-mode rules as a failure for exactly this
reason.

## 6. After the pilot

Only once the pilot is clean: run `03-Set-AsrBlock.ps1` against the remaining clients (or move the
setting from local preference into the Defender GPO). Record the final state per client in
`p04-ph2-asr-block-result.csv`, paste the summary into `README.md`, and tick `docs/as-built.md` §3.
