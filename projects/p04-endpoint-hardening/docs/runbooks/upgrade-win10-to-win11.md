# Runbook — In-place upgrade of a Windows 10 device to Windows 11

**Applies to:** any Windows 10 device that passed the readiness check (`upgrade` status)
**Time:** about 90 minutes per device, of which roughly 40 is waiting · **Owner:** IT / Systems
**Change:** CHG-2026-004 (P4) · **Rollback window:** until the user starts working on the upgraded build

> This is the checklist the readiness report promises management. It is written to be followed by
> someone other than its author, on a weekday, without drama.

## 0. Preconditions

- [ ] The device is classified **`upgrade`** by `scripts/07-Get-Win11Readiness.ps1` (TPM 2.0, Secure
      Boot, UEFI, supported CPU, 4 GB+ RAM, 64 GB+ disk). A `replace` device is not upgraded — see
      the readiness report for why.
- [ ] The user has been told the date and duration, and their work is saved and closed.
- [ ] A verified backup exists (P8 restic/PBS snapshot, or at minimum the user's files are on the
      file server and OneDrive-style sync is not relied on as the only copy).
- [ ] A hypervisor snapshot or an image-level backup exists: `snap-p4-ph6-win10-before`.
- [ ] The device is plugged into power (never upgrade on battery) and, for a VM, the vTPM is present.
- [ ] The Windows 11 installation media or in-place upgrade assistant is available and **its hash is
      recorded** so you know exactly what was installed.

## 1. Record the "before" state

```powershell
systeminfo | Select-String 'OS Name', 'OS Version', 'System Model'
Get-Tpm | Select-Object TpmPresent, TpmReady, SpecVersion
Confirm-SecureBootUEFI
Get-BitLockerVolume -MountPoint C: | Select-Object MountPoint, ProtectionStatus, EncryptionMethod
Get-Volume | Select-Object DriveLetter, FileSystemLabel, @{n = 'FreeGB'; e = { [math]::Round($_.SizeRemaining / 1GB, 1) }}
```

Save the output to `evidence/raw/` — the disk free space and the BitLocker state are the two facts you
will want afterwards if the upgrade misbehaves.

## 2. Compatibility check

1. Run **PC Health Check** (or the readiness script's output) on the device and confirm it reports
   Windows 11 supported.
2. Check the **critical line-of-business applications** the user actually runs, not the full installed
   list. For each: is there a Windows 11 compatible version, and is it installed or packaged?
3. Check any peripherals the user depends on (a scanner, a label printer, a USB stock gun) for a
   Windows 11 driver.
4. Note anything unverified. An unverified application is a risk to state out loud, not to discover at
   the user's desk.

## 3. Application and data test (before the upgrade)

- [ ] Business application opens, and the user's main task runs end to end on the **current** build, so
      you know the task worked before you changed anything.
- [ ] Files in the user's profile and on mapped drives are present and openable.
- [ ] BitLocker is on and **the recovery key is escrowed** (check the computer object in AD). If the
      upgrade resets the key protector, you need the escrow route to work.

## 4. Upgrade

1. Start the in-place upgrade from the recorded media. Keep the device on power and do not interrupt.
2. Watch for the two decision points that matter: keeping files and applications (never a clean
   install on a user's device without a specific reason in the ticket), and the TPM/Secure Boot
   prompt if it appears.
3. After the reboot cycle completes, sign in as **yourself first** and check the basics before the
   user touches it.

## 5. Post-upgrade checks

```powershell
(Get-CimInstance Win32_OperatingSystem).Caption        # expect a Windows 11 caption
[Environment]::OSVersion.Version.Build                  # record the build number
Get-BitLockerVolume -MountPoint C: | Select-Object ProtectionStatus, EncryptionMethod, EncryptionPercentage
Get-MpComputerStatus | Select-Object RealTimeProtectionEnabled, AntivirusSignatureAge
```

- [ ] Windows 11 caption and build recorded on the ticket.
- [ ] BitLocker still `On`; if a new recovery password was created, **confirm it is escrowed** (the
      same rule as the recovery runbook — an unescrowed key is what you must not leave behind).
- [ ] Defender running with current signatures.
- [ ] Group Policy applied: `gpupdate /force`, then `gpstat`/`gpresult` — the baseline, firewall and
      local-admin policies must all still be present.
- [ ] **Local Administrators still contains only the approved members** — an upgrade can reintroduce a
      member, and this is the exact check the compliance report runs.
- [ ] Business application opens and the main task works.
- [ ] Mapped drives and the default printer are back.
- [ ] The user signs in and completes one real task before you close the ticket.

Then run the compliance script against the device and add the result to the P4 evidence:

```powershell
.\scripts\06-Get-EndpointCompliance.ps1 -ComputerName <device>
```

## 6. Rollback

The rollback window is the period in which Windows keeps the previous installation
(`Windows.old`), typically **10 days**.

| Situation | Action |
|---|---|
| Something is broken and the user must work today | **Roll back** (Settings → System → Recovery → "Go back"), restore from the snapshot, then fix forward on a test device before trying again |
| A single application fails | Do not roll back the whole device first — check for a compatible version, and record the failure |
| The rollback window has passed | Recovery is a reimage and a re-install of applications: slower, and the reason to test the critical application *before* the upgrade |
| The device will not boot | Restore the snapshot; if the VM/disk image is the only copy, that is why step 0 requires a backup |

**Never** roll back by deleting a BitLocker key protector or the escrow record.

## 7. Record the outcome

| Fact | Where |
|---|---|
| Time taken (start → user working) | Ticket, and the readiness report's cost figures are corrected from the real number |
| Applications that needed attention | Ticket + the readiness report's risk section |
| Compliance result after upgrade | `reports/endpoint-compliance-<date>.html` |
| BitLocker escrow confirmed | `p04-ph3-bitlocker-escrow-result.csv` (key ID and escrow result only, never the key) |

Do the first upgrade on a **test device**, not on a user's laptop, and write down what surprised you.
The readiness report's "labour per device" figure is only credible once it comes from a real upgrade.
