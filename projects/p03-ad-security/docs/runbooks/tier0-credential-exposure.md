# Runbook — A Tier 0 credential may be exposed

**Applies to:** DC01, DC02 and the whole domain · **Severity:** Critical (Tier 0) ·
**Owner:** IT / Systems · **When:** any sign that a domain administrator credential, a krbtgt
value, a DCSync-capable account or a Tier 0 host may be in the wrong hands

## Why

A Tier 0 credential is not "an account with more rights". It is the ability to change the directory
itself: create accounts, grant rights, read every hash, and persist. Treating a suspected exposure
as urgent is the whole point of the tiering model — and having the response written down *before* it
happens is what turns a panic into a procedure.

## 0. First 30 minutes — contain, do not investigate

| Step | Action | Why |
|---|---|---|
| 1 | **Do not disable the account first.** Confirm whether the person is still working | Disabling a working admin mid-incident turns a security event into an outage |
| 2 | Change the password of the affected admin account from a **different, trusted** Tier 0 session | If the exposed session is compromised, resetting from it gives the attacker the new password too |
| 3 | Reset the password **twice** for a krbtgt exposure: reset, wait at least the maximum ticket lifetime (default 10 hours) plus replication, reset again | One reset leaves tickets issued under the old key valid; the plan's pitfall list warns about doing both too quickly |
| 4 | Revoke the sessions: sign out the account everywhere and clear cached credentials. For a Tier 0 PAW, rebuild it rather than clean it | A workstation that held a Tier 0 credential can no longer be trusted |
| 5 | **Do not delete anything.** Preserve the security log and the evidence | Attribution and scope depend on the logs you keep |
| 6 | Notify the owner and record the incident reference | Rule R6 and the change/incident trail |

## 1. Scope the exposure with real evidence

Run these from a trusted Tier 0 session. Read them as questions: *did this credential actually get
used, and where?*

```powershell
# 1. When did the account last authenticate, and from where?
Get-ADUser <sam> -Properties LastLogonDate, LastBadPasswordAttempt, PasswordLastSet
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4624} -MaxEvents 200 |
  Where-Object { $_.Message -match '<sam>' } | Select-Object TimeCreated, Id

# 2. What does the account actually hold? (rights, not just membership)
.\scripts\10-Test-PrivilegedAccess.ps1

# 3. Is there evidence of directory-wide credential use?
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4662} -MaxEvents 200   # DCSync shows as a replication right
Get-WinEvent -FilterHashtable @{LogName='Security'; Id=4769} -MaxEvents 200   # Kerberos service tickets
```

On the identity side, confirm nothing was added while the credential was exposed:

```powershell
Get-ADGroupMember 'Domain Admins' | Select-Object SamAccountName
Get-ADUser -Filter 'adminCount -eq 1' -Properties adminCount, WhenChanged | Sort-Object WhenChanged -Descending | Select-Object -First 20
Get-ADObject -Filter { whenChanged -gt (Get-Date).AddHours(-24) } -Properties whenChanged |
  Select-Object Name, ObjectClass, whenChanged | Sort-Object whenChanged -Descending
```

## 2. Related exposures and how to close each

| Exposure | How it is closed in this project |
|---|---|
| Kerberoastable service account (a crackable hash copied from the network) | Move the SPN to a gMSA, then disable the legacy account — Phase 5, `08-Set-ServiceAccountHygiene.ps1` |
| Unconstrained delegation (a server that can be made to authenticate anywhere) | Remove the delegation flag; use constrained or resource-based delegation if it is genuinely needed — Phase 2 |
| Accounts that skip Kerberos pre-authentication (offline-crackable challenge) | Clear `DoesNotRequirePreAuth` — Phase 2 |
| Shared local administrator password | Windows LAPS with encryption, unique per endpoint, 30-day rotation — Phase 3 |
| A plaintext Tier 0 password sitting in a script or a note | Move it into the password manager; re-read `AGENTS.md` Section 6 and rotate the credential |

## 3. Afterwards — fix the reason it was possible

- **Tier 0 accounts have no email, no browsing and no workstation logon.** If a Tier 0 credential
  was usable from a workstation, the deny-logon rules are not working. Test them: a Tier 0 account
  attempting RDP to WS01 must be refused.
- **Protected Users** should already cover the human Tier 0 accounts (no NTLM, no delegation, no
  cached credentials, 4-hour TGT). Verify membership, and remember that no service or computer
  account may be added.
- **Reset or rotate anything derivable.** If a Tier 0 account was exposed, assume any credential it
  could read is exposed too: LAPS passwords it was a decryptor for, and any service account whose
  password it could reset.
- **Write it into the review.** Add the cause to the next monthly privileged-access review and, once
  P7 exists, turn the relevant events into an alert instead of a manual search.

## Rollback

There is no rollback for a credential: once it is used by someone else, it can never be trusted
again. The account is either reset or deleted; the only reversible part is the access the account
held, which is restored deliberately by re-adding a *new* account after the incident is closed.

> This runbook assumes the assets are the owner's isolated lab. In a real engagement, the same
> sequence applies but legal, HR and the business owner are involved before any account is changed.
