# Runbook — A member of staff is leaving (written for HR and line managers)

**Applies to:** HR, line managers, IT · **Target:** access removed within 15 minutes of the leaver
being recorded · **Owner:** IT Support
**Who does what:** HR records the leaver in the HR system; IT's automation removes the access. HR and
the line manager do **not** need to do anything technical — but the process only starts when HR
records the leaver, so step 1 is the one that matters.

> Why this is written for a non-technical reader: the most common offboarding failure is not a
> technical one. It is that nobody told IT, so the account stayed open. This runbook exists so that
> "tell HR, then record it" is a process a department can follow, not a favour someone remembers.

## What happens, in plain English

1. **HR records the leaver.** Open the leaver in the HR system and set `Status` to `Leaver` with the
   last working day in `EndDate`. That is the trigger — nothing else is needed from HR.
2. **Tell the line manager** so they can collect equipment and hand over work. This is a business
   task, not an IT task.
3. **IT's automation runs** on its schedule (at least daily), sees the leaver, and:
   - disables the account,
   - resets the password so nobody can use the old one,
   - removes the person from every group (so all their folder and application access stops),
   - records what access they *had* before it was removed (needed for investigations and rehires),
   - moves the account to the `Disabled` area of the directory.
4. **IT confirms it is done.** The audit log holds a dated line showing the account was disabled by
   the automation. IT can tell HR "done" with a time.
5. **The account is kept, not deleted, for 90 days.** It is disabled and stripped of access but the
   record stays, in case of a legal hold, a payroll query or a rehire. Deletion happens later, after
   a report and a check.

## For HR — how to do step 1

1. In the HR system, find the employee by **employee number**, not by name (names repeat and get
   misspelt; the number does not).
2. Set **Status** to `Leaver`.
3. Set **EndDate** to the last working day. If the person must be cut off immediately, note that in
   the leaver comment **and call the IT Service Desk** — there is a separate "immediate leaver"
   path for urgent cases (for example a dismissal or a security concern).
4. Save. That is the whole HR step.

## For the line manager

- Collect the laptop, phone, pass and keys on the last day, and return the equipment to IT.
- Tell IT about anything the leaver was the only person able to do (for example "she was the only one
  who knew the supplier portal"), so the access can be reassigned deliberately rather than lost.
- Do **not** ask IT to "keep their access for a bit just in case". If continuing access is genuinely
  needed, that is a new, time-limited approval from the department head, recorded like any other
  access change.

## For IT — verification and the urgent path

1. **Check the automation ran** and produced an audit entry for this `EmployeeID`:
   ```powershell
   Import-Csv .\logs\jml-audit.csv | Where-Object { $_.Target -eq '<EmployeeID>' -and $_.Action -eq 'Leaver' }
   ```
2. **Confirm the account state** — disabled, in `OU=Disabled`, and out of all groups but
   `Domain Users`:
   ```powershell
   $u = Get-ADUser -Filter "EmployeeID -eq '<EmployeeID>'" -Properties MemberOf,Enabled,Description
   $u | Select-Object SamAccountName,Enabled,Description
   (Get-ADPrincipalGroupMembership $u).Name
   ```
3. **Confirm the leaver snapshot exists** (this is the record of what they could reach):
   ```powershell
   Get-Content .\logs\leavers\<EmployeeID>.json
   ```
4. **Cloud side** (once hybrid identity is live): sign-in sessions revoked, sign-in blocked, mailbox
   handled, then licence removed. Check the audit log for the cloud actions.
5. **Immediate leaver:** do not wait for the schedule. Run the engine for that one person with the
   urgent flag (it skips the date check), then verify as above:
   ```powershell
   .\scripts\01-Invoke-HaldenJML.ps1 -EmployeeID '<EmployeeID>' -Urgent
   ```

## Verification (what "done" looks like)

- The audit log has a dated `Leaver` record for the `EmployeeID`.
- The account is disabled and sits in `OU=Disabled`.
- The only group left is `Domain Users`.
- `logs/leavers/<EmployeeID>.json` exists and lists the old memberships.
- Any cloud licence is released (or a note says why it was deferred for mailbox handling).

## Rollback

A leaver processed in error is restored from the snapshot, not from memory:

1. Re-enable the account and move it back to its department OU.
2. Re-add the groups listed in `logs/leavers/<EmployeeID>.json`.
3. Correct the HR record (`Status` back to `Active`) so the next engine run does not disable it again.
4. Record the correction in the audit log and in the ticket.

> Never restore access without the HR record being corrected first — otherwise the automation will
> simply disable the account again on its next run.
