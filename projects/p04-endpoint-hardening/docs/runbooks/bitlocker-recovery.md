# Runbook — Recover a BitLocker-protected device with IT's escrowed key

**Applies to:** any BitLocker-protected Halden client · **Severity:** High (user cannot work)
**Owner:** IT Support (Tier 1) with a Tier 2 escalation · **Time:** 15–30 minutes

> **The rule that matters most: verify the person before you give them the key.** Recovery-key
> retrieval is a real social-engineering target. Someone who can talk the helpdesk into reading a key
> aloud gets permanent access to a laptop full of Finance or HR data.

**Never** copy a recovery key into an email, a chat message, a ticket comment or this repository.
The key stays in the vault (Active Directory, or the owner's password manager) and is read to the
verified user over a channel you control.

## 0. When a device asks for a recovery key

The user sees the blue BitLocker recovery screen with a **Recovery key ID**. Typical causes:

| Cause | Clue |
|---|---|
| TPM cleared or firmware/BIOS change | The device was recently updated or repaired |
| Secure Boot configuration changed | Often follows a Windows update on a virtual machine |
| User forgot a PIN (if TPM + PIN was configured) | Device prompts before the OS loads |
| Motherboard or disk replaced | Hardware change on a returned repair |
| Deliberate `manage-bde -forcerecovery` | Only during a recovery test |

## 1. Identify the device and the caller (do not skip)

1. Ask for the user's **full name, department and staff ID**, and the **hostname** shown on the
   recovery screen. Cross-check the user against the device's owner in the CMDB (P9) or, until then,
   the AD computer object.
2. Ask a question only that user is likely to answer, or call them back on the number in the IT
   register. Do **not** call the number the caller gives you.
3. If the device holds Finance, HR or management data, or the caller is not the registered owner,
   **escalate to Tier 2 before releasing anything**. A director asking urgently for another
   department's laptop is a red flag, not a priority.

Record on the ticket: who called, when, how identity was verified, and who approved release.

## 2. Find the recovery key

From a domain-joined management host, with an account in the group delegated to read recovery
information:

```powershell
# 1. Does the computer have an escrowed recovery password?
Get-ADComputer WS01 -Properties msTPM-OwnerInformation |
  Select-Object Name, DistinguishedName

Get-ADObject -Filter 'objectClass -eq "msFVE-RecoveryInformation"' `
  -SearchBase (Get-ADComputer WS01).DistinguishedName `
  -Properties msFVE-RecoveryPassword, whenCreated |
  Select-Object Name, whenCreated, msFVE-RecoveryPassword
```

**Screen-share caution:** this output contains the password. If you screenshot it for evidence, crop
the `msFVE-RecoveryPassword` column out entirely before the image goes anywhere near `evidence/`
(AGENTS.md 4.6). The saved evidence should be the **key ID and the escrow date**, never the value.

If **no** `msFVE-RecoveryInformation` object exists, the key was never escrowed. Stop and escalate to
Tier 2: do not attempt to recover the data by other means, and treat the missing escrow as an incident
(the device may need to be rebuilt, and data loss is now a real risk).

## 3. Read the key to the verified user

- Read the 48-digit recovery password over a channel you control, or have the user type it directly
  while you watch the screen if you are on site.
- The device unlocks and boots normally. Confirm the user can sign in and reach their files and drives.
- Tell the user to keep the recovery screen open until the device is fully booted, and not to write
  the key down and leave it under the laptop.

## 4. Afterwards

1. **Check why recovery was triggered** (section 0) and record the cause on the ticket.
2. If the trigger was a deliberate test, record the **time taken** from the recovery screen appearing
   to the user signing in — that number is the evidence for the README, not an estimate.
3. If the trigger was a hardware change, confirm the volume is still `ProtectionStatus = On` and the
   key protector is still present:

```powershell
Get-BitLockerVolume -MountPoint C: | Select-Object MountPoint, ProtectionStatus, KeyProtector
```

4. If a new recovery password was generated during recovery, **confirm it is escrowed** before the
   device leaves your hands. An unescrowed new key is the same problem again, later.
5. Close the ticket with: cause, verification method, who approved release, and time to recover.

## 5. Prevention checks (add to the weekly routine)

- Every computer object in the Workstations OU has an `msFVE-RecoveryInformation` object.
- The compliance report (C2, BitLocker) passes — protection on and 100% encrypted.
- No BitLocker recovery key has ever been committed to the repository or pasted into a ticket:
  `gitleaks detect --no-git` must stay clean.

**Rollback / failure path:** if the key does not unlock the device, do **not** delete it. Escalate to
Tier 2 with the recovery key ID and the escrow date; a wrong key usually means the wrong device or a
stale key, and deleting the escrow record destroys the only recovery path left.
