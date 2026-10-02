# P3 as-built — Halden AD security and privileged access

> **Status: build kit complete, lab execution pending.** This document records the *designed*
> configuration from [`00-design.md`](./00-design.md) and is written so that the *measured* facts
> can be pasted straight in. Nothing here is presented as a captured result: the **Verified**
> column stays empty until the matching script has actually run in the lab. No score, no path
> count and no configuration value in this file has been observed yet.
>
> **How to finish this document:** run `scripts/11-Verify-Remediation.ps1` and
> `scripts/10-Test-PrivilegedAccess.ps1` on DC01. They write the verification CSV and the exception
> CSV under `evidence/raw/`. Sanitize that output (AGENTS.md 4.6), paste it into the sections below,
> and tick the Verified column. Evidence files go in `evidence/public/` with names like
> `p03-ph7-laps-backup-result.png`.
>
> **Authorisation:** the assessment tooling (PingCastle, Purple Knight, BloodHound CE) is run only
> inside this isolated lab, only against `ad.halden.internal`, and only after the owner's written
> authorisation (AGENTS.md rule R6). The gate script records the reference.

## 1. Environment summary

| Item | Designed value | Verified |
|---|---|---|
| Domain | `ad.halden.internal` | ☐ |
| Forest / domain functional level | Windows Server 2025 | ☐ |
| Domain controllers | DC01 (192.168.10.10), DC02 (192.168.10.11) | ☐ |
| Member servers in scope | FS01 (192.168.10.20), LNX01 (192.168.10.30) | ☐ |
| Workstations in scope | WS01 (user), WS02 (Tier 0 PAW) | ☐ |
| Assessment authorisation reference | `CHG-2026-004` (change record) | ☐ |
| Assessment tools | PingCastle basic, Purple Knight, BloodHound CE, Windows LAPS | ☐ |

## 2. Assessment results *(designed placeholders — to be measured)*

| Metric | Before | After | Source | Verified |
|---|---|---|---|---|
| PingCastle global risk score | not measured | not measured | `evidence/public/p03-ph7-pingcastle-score-after.png` | ☐ |
| PingCastle — Stale Objects category | not measured | not measured | pending | ☐ |
| PingCastle — Privileged Accounts category | not measured | not measured | pending | ☐ |
| PingCastle — Trusts category | not measured | not measured | pending | ☐ |
| PingCastle — Anomalies category | not measured | not measured | pending | ☐ |
| Purple Knight critical indicators open | not measured | not measured | pending | ☐ |
| BloodHound paths from Domain Users to Domain Admins | not measured | not measured | `evidence/public/p03-ph7-bloodhound-after.png` | ☐ |

## 3. Seeded weaknesses (Phase 0, deliberately introduced)

The seed script is idempotent and lab-guarded. This table records what was seeded; the *result*
column is ticked only after `01-Seed-Weaknesses.ps1` has run and the seed log
(`evidence/raw/p03-ph0-seed-log.csv`) confirms each action.

| Seeded weakness | How | Seeded? |
|---|---|---|
| Kerberoastable service account | `svc-sql` with SPN `MSSQLSvc/lnx01.ad.halden.internal:1433`, never-expiring weak password | ☐ |
| AS-REP-roastable user | one Sales user with "do not require Kerberos pre-authentication" | ☐ |
| Unconstrained delegation | `TrustedForDelegation` on FS01 | ☐ |
| Excess and stale Domain Admins | four users added, one of them disabled | ☐ |
| Shared local administrator password | identical `LocalAdmin` password on WS01 | ☐ |
| Weak domain password policy | 7 characters, no lockout | ☐ |
| Legacy protocols | LM compatibility level 1, SMB signing not required, Spooler running on DCs | ☐ |
| AD Recycle Bin disabled | recorded, not changed | ☐ |
| Old krbtgt password | recorded, not changed | ☐ |

## 4. Quick wins (Phase 2) *(designed)*

| Control | Designed value | Verified |
|---|---|---|
| AD Recycle Bin | Enabled, forest-wide | ☐ |
| Domain Admins membership | Tier 0 admin accounts plus the built-in Administrator only | ☐ |
| Accounts skipping Kerberos pre-authentication | none | ☐ |
| Unconstrained delegation | none | ☐ |
| Print Spooler on DCs | service disabled; GPO `DC - Disable Print Spooler - v1` | ☐ |
| `FGPP-Admins` | precedence 10, 20 characters, lockout 5 / 30 min, max age 180 days, applies to `G_Tier0_Admins` and `G_Tier1_Admins` | ☐ |
| Default domain policy | minimum 14 characters, lockout 10 / 15 min | ☐ |

## 5. Windows LAPS (Phase 3) *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Schema | `Update-LapsADSchema` completed, `ms-LAPS-Password` present | ☐ |
| Backup directory | Active Directory | ☐ |
| Password complexity | large + small + numbers + specials, length 20 | ☐ |
| Password age | 30 days, expiration protection on | ☐ |
| Encryption | `ADPasswordEncryptionEnabled` = enabled | ☐ |
| Authorised decryptors | workstations → `G_Tier2_Helpdesk`; servers → `G_Tier1_ServerAdmins`; DCs → `G_Tier0_Admins` | ☐ |
| Post-authentication action | reset password and log off after 8 hours | ☐ |
| DSRM password backup for DCs | enabled | ☐ |
| Backup evidence | Event 10018 present in `Microsoft-Windows-LAPS/Operational` | ☐ |
| Access control | helpdesk `Get-LapsADPassword` succeeds; a standard user is denied | ☐ |

## 6. Tiering model (Phase 4) *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| `_Admin` OU tree | `Tier0\|Tier1\|Tier2\Accounts\|Groups`, plus `PAW\Devices` | ☐ |
| Admin account naming | `adm-t{tier}-first.last` | ☐ |
| Tier groups | `G_Tier0_Admins`, `G_Tier1_Admins`, `G_Tier2_Admins`, `G_Tier1_ServerAdmins`, `G_Tier2_Helpdesk` | ☐ |
| Admin account flags | not delegable, no pre-auth skip, password expiry on | ☐ |
| Protected Users | human Tier 0 accounts only (test account proven first) | ☐ |
| Workstation logon rights | deny interactive, RDP, batch and service logon to `G_Tier0_Admins`, `G_Tier1_Admins` | ☐ |
| Server logon rights | deny interactive and RDP to `G_Tier0_Admins`, `G_Tier2_Admins` | ☐ |
| DC logon rights | only `G_Tier0_Admins`; deny RDP to Tier 1 and Tier 2 admins | ☐ |
| PAW | WS02 in `_Admin\PAW\Devices`; network isolation added in P6 | ☐ |
| Helpdesk delegation | Reset Password and unlock on the six user OUs only, never on Tier 0 objects | ☐ |
| Tier 0 admin can RDP to WS01 | denied (tested, not assumed) | ☐ |
| Helpdesk can reset a Sales user but not a Tier 0 admin | confirmed by test | ☐ |

## 7. Service accounts and Kerberos (Phase 5) *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| KDS root key | created (lab-only effective time) | ☐ |
| gMSA | `gmsa-sql`, AES256 only, password retrievable by `G_Tier1_ServerAdmins` | ☐ |
| Legacy account | `svc-sql` disabled, SPN moved to the gMSA | ☐ |
| `Test-ADServiceAccount gmsa-sql` | True | ☐ |
| Kerberos encryption | audit first (event 4769, RC4 = 0x17), then AES-only | ☐ |
| krbtgt | simulation only; rotation is a separate scheduled change | ☐ |

## 8. Legacy protocols (Phase 6) *(designed)*

| Setting | Designed value | Verified |
|---|---|---|
| LAN Manager authentication level | 5 — send NTLMv2 only, refuse LM and NTLM | ☐ |
| NTLM auditing | incoming NTLM audited for all accounts; event 8004 reviewed before enforcing | ☐ |
| SMB signing | required on server and workstation | ☐ |
| SMBv1 | feature disabled on DC01, DC02, FS01, WS01 | ☐ |
| LDAP signing | `LDAPServerIntegrity` = 2 (require signing) on DCs | ☐ |
| LDAP channel binding | `LdapEnforceChannelBinding` = 2 (always) on DCs | ☐ |
| LLMNR | disabled by policy | ☐ |
| NetBIOS over TCP/IP | recorded; disabled where it is not needed | ☐ |

## 9. Privileged access review *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Review frequency | monthly for the automated checks, quarterly for the human sign-off | ☐ |
| Script | `scripts/12-Invoke-PrivilegedAccessReview.sh` (read-only) | ☐ |
| Exception source | `evidence/raw/p03-ph5-privilege-audit-result.csv` | ☐ |
| Residual risk | risk-acceptance entries with a named owner and review date | ☐ |

## 10. Known gaps and exceptions

| Item | Note |
|---|---|
| Trusts category of PingCastle | One forest, no trust relationships: this category has little to assess here. Recorded honestly rather than presented as a strength. |
| Hybrid (Entra) exposure | Entra Connect arrives in P2 and is out of scope for the P3 measurement; the tiering model already treats it as Tier 0. |
| PAW network isolation | WS02 is *designated* the PAW in P3 but is only truly isolated by the P6 firewall rules. Between P3 and P6 this is an accepted gap. |
| Break-glass account | The built-in Administrator is excluded from the deny-logon rules and its password is stored offline. This is a deliberate exception and is reviewed, not forgotten. |
| No exploit is executed | The assessment maps reachability and configuration. It does not crack credentials or run an exploit chain. |
| Scale | "100% LAPS coverage" is true of a handful of lab VMs, not of a real mixed-hardware fleet. |

## 11. How this document gets finished

1. Run the gate, the seed, the assessment, the hardening and the verification scripts in order
   (see `README.md`).
2. Sanitize every output per AGENTS.md 4.6 — in particular, blur any LAPS password value.
3. Paste the real values into §2–§9 and tick **Verified** only where a source file exists.
4. Copy the headline metrics into `README.md` with the source file named, and update
   `showcase.md`'s metrics only then (it currently has none, deliberately).
