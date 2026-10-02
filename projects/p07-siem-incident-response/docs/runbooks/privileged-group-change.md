# Runbook — Privileged group change

**Applies to:** DC01, DC02 · **Severity:** SEV1 if unapproved, SEV3 if approved · **Owner:** on-call analyst
**Detections covered:** D1 (100100 member added to a privileged group), D8 (100108 security log
cleared), D10 (100111 Tier 0 / break-glass logon), D11 (100105 DCSync).
**Target:** this is the shortest path to domain takeover. Establish in minutes whether the change
was approved, and contain if it was not.

## 0. The question that decides everything

**Was this change approved?** Check, in this order:

1. The change log (P10) — is there an approved change record for this window?
2. The JML audit (P2) — is this a legitimate joiner/mover who needs the role?
3. The person named as `subjectUserName` — did they make the change, and did they say so?

If there is **no** matching approval, treat as SEV1. If there is a clean, approved change, record
that and close as SEV3 — but still confirm the change is what the ticket said.

## 1. First five minutes

```powershell
# Who was added, to what, by whom, and when?
$ev = Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4728,4732,4756 } -MaxEvents 20
$ev | Select-Object TimeCreated, @{n='Msg';e={$_.Message}} | Format-List

# Current members of the sensitive group — confirm the change is (or is not) still in place.
Get-ADGroupMember 'Domain Admins' | Select-Object Name, SamAccountName, ObjectClass
```

| Field | What to read from it |
|---|---|
| `targetUserName` | The group (Domain Admins, Enterprise Admins, Schema Admins, Administrators) |
| `memberName` | The account that was added |
| `subjectUserName` | The account that did the adding — the one to scope |
| `win.system.computer` | Which DC recorded it |

## 2. Contain (if unapproved)

1. **Remove the membership** (reversible), then disable the account that was added.
2. **Disable the source account** (`subjectUserName`) only after preserving evidence — it is the
   likely compromised identity.
3. **Isolate the host** the source account was used from.
4. Check for the correlated alerts in the same window: D10 (where did that account log on?), D11
   (did they try to replicate the directory?), D6/D9 (did they leave persistence?).

## 3. Scope — assume they did more than one thing

```powershell
# Everything the source account did in the window, on both DCs.
Get-WinEvent -FilterHashtable @{ LogName='Security'; Id=4720,4728,4732,4740,4756; StartTime=(Get-Date).AddHours(-24) } |
  Where-Object { $_.Message -match '<source-account>' } | Select-Object TimeCreated, Id
```

- Other group changes, new accounts, password resets, new services or tasks.
- Any DCSync attempt (D11) — that means the directory was likely already dumped; assume all
  credentials in scope are compromised.

## 4. Preserve

- Export the 4728/4732/4756 events and the correlated alerts before making changes.
- Record the current group membership as it was found (that is evidence too).
- Write the timeline as you go (`data/incident-timeline-template.md`).

## 5. Recover

- Restore the correct membership only after the source of the change is understood and closed.
- Reset the passwords for any accounts the attacker could have touched (and expect that anyone the
  compromised account could reach is also in scope).
- If the directory was replicated (D11), a full credential reset is the safe assumption.

## 6. Close out

- Incident report; if unapproved, this is SEV1 and the MD is informed.
- Add the prevention: a Protected Users / tiering control if this exposed a gap (P3), or a narrower
  approval process (P10).

## Rollback

Removing and re-adding a group membership is fully reversible and is preferred over deleting the
group. Account disables are reversible after a reset. Host isolation is reversed by returning it to
its VLAN.

> **Lab note:** D1 is validated in the lab by a deliberate, approved, snapshotted change (add then
> remove a dedicated `adm-t0-*` test account) — never by leaving an unauthorised member in place.
> See `scripts/07` and the AGENTS.md R6 approval rule.
