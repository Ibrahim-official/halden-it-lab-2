# P4 as-built — Halden endpoint hardening and Windows 11 readiness

> **Status: build kit complete, lab execution pending.** This document records the *designed*
> values from [`00-design.md`](./00-design.md) and the config files, written so the *measured* facts
> can be pasted straight in. Nothing here is presented as a captured result: the **Verified**
> column stays empty until the matching script has actually run in the lab and the compliance report
> has produced its output.
>
> **How to finish this document:** run the phase, then paste the real output into the section and
> tick its **Verified** box. Evidence files go in `evidence/public/` with names like
> `p04-ph2-asr-block-result.csv` and `p04-ph3-bitlocker-escrow-result.png`. Every published figure
> must be traceable to one of those files (AGENTS.md 4.5). Any screenshot of the AD escrow check
> must have the recovery-password column cropped out (AGENTS.md 4.6).

## 1. Environment summary

| Item | Designed value | Verified |
|---|---|---|
| Domain | `ad.halden.internal` | ☐ |
| Clients in scope | WS01 (policy/compliance client), WS02 (Tier 0 PAW, added in P3) | ☐ |
| Client OS | Windows 11 Enterprise evaluation (90-day) | ☐ |
| Windows 10 test client | one VM upgraded in Phase 6 | ☐ |
| Hypervisor | Hyper-V on Windows 11 Pro (HOST01, 16 GB host RAM) | ☐ |
| Baseline GPO | `WKS - MSFT Baseline Computer - v1` | ☐ |
| Overrides GPO | `WKS - Halden Overrides - v1` (higher precedence) | ☐ |
| Hardening GPO | `WKS - Windows Hardening - v1` | ☐ |
| Management subnet | 192.168.40.0/24 (applied in P6; designed here) | ☐ |

## 2. Baseline import (Phase 1)

| Fact | Designed value | Verified |
|---|---|---|
| Baseline source | Microsoft Security Compliance Toolkit (Windows 11 security baseline) | ☐ |
| Import method | `Import-GPO` into a new GPO, never editing Microsoft's backup | ☐ |
| Conflict review | Policy Analyzer comparison against the P1–P3 GPOs, exported | ☐ |
| Rollout rings | Pilot OU (`Workstations\Pilot`, WS02) for 3 days, then the Workstations OU | ☐ |
| Deviations | `WKS - Halden Overrides - v1`, one row per deviation in the exceptions register | ☐ |
| GPO backup committed | `configs/gpo-backup/` | ☐ |

## 3. Defender and ASR (Phase 2)

| Setting | Designed value | Verified |
|---|---|---|
| PUA protection | Enabled | ☐ |
| Cloud block level | High | ☐ |
| Cloud extended timeout | 50 seconds | ☐ |
| MAPS reporting | Advanced | ☐ |
| Sample submission | Send safe samples | ☐ |
| Network protection | Enabled | ☐ |
| Controlled Folder Access | Audit mode first | ☐ |
| ASR rules deployed | 16 (see `configs/asr-rules.yaml`) | ☐ |
| Initial mode | Audit (value 2) for at least 7 days | ☐ |
| Review channel | `Microsoft-Windows-Windows Defender/Operational`, event 1122 audited | ☐ |
| Final mode | Block (value 1) for the approved set; event 1121 confirms | ☐ |
| Rule 9 (PSExec/WMI) | Deliberately reviewed before any block | ☐ |
| Exclusions | None without a row in `business/p04-asr-exceptions.md` | ☐ |
| Tamper protection | On in Windows Security; centrally managed only with Intune/MDE (known gap, §10) | ☐ |

## 4. BitLocker (Phase 3)

| Setting | Designed value | Verified |
|---|---|---|
| Encryption algorithm | XTS-AES 256 | ☐ |
| OS drive startup protector | TPM-only (no PIN) for standard devices | ☐ |
| Recovery protector | Recovery password added to every protected volume | ☐ |
| Escrow target | Active Directory DS (`msFVE-RecoveryInformation`) | ☐ |
| Escrow order | Policy in place before encryption (enforced by the script guard) | ☐ |
| Fixed drives | Encrypted where present | ☐ |
| Encryption scope | Full disk (`UseUsedSpaceOnly` off) | ☐ |
| Recovery test | Forced recovery, helpdesk retrieval, unlock, time recorded | ☐ |
| Keys in the repository | None — by design; the evidence CSV holds key protector IDs only | ☐ |

## 5. Local admins and remaining hardening (Phase 4)

| Item | Designed value | Verified |
|---|---|---|
| Local `Administrators` members | `Administrator` (LAPS-managed, P3) + `G_Tier2_Admins` | ☐ |
| `Domain Users` in Administrators | Removed | ☐ |
| Delivery | GPP Local Users and Groups, "delete all member users/groups" (lab: applied directly) | ☐ |
| Firewall | On for domain, private and public; inbound default block | ☐ |
| RDP / WinRM source | Management subnet 192.168.40.0/24 only | ☐ |
| Credential Guard | Enabled where VBS-capable; verified with `msinfo32`, not assumed | ☐ |
| LSA protection | `RunAsPPL = 1` | ☐ |
| PowerShell logging | Script block logging and module logging on | ☐ |
| AppLocker | Audit mode only (stretch goal; not enforced) | ☐ |

## 6. Compliance report (Phase 5)

| Control | Pass condition | Verified |
|---|---|---|
| C1 OS build | Build ≥ 22631 | ☐ |
| C2 BitLocker | Protection On and 100% encrypted | ☐ |
| C3 Defender | Real-time on, signatures < 24 h, quick scan < 7 days | ☐ |
| C4 ASR | 0 auditing, ≥ 16 blocking | ☐ |
| C5 Firewall | All three profiles enabled | ☐ |
| C6 Local admins | Approved members only | ☐ |
| C7 LAPS | Password set within 31 days (update time only) | ☐ |
| C8 Pending reboot | False | ☐ |
| C9 Last patch | Within 35 days | ☐ |
| Report outputs | `reports/endpoint-compliance-<date>.html` and `.csv` | ☐ |
| Schedule | Daily from a management server | ☐ |

## 7. Windows 11 readiness (Phase 6)

| Item | Designed value | Verified |
|---|---|---|
| Rules file | `configs/win11-readiness-rules.yaml` | ☐ |
| Shared implementation | `data/fleet_rules.py` (Python) and `scripts/07-Get-Win11Readiness.ps1` (PowerShell) | ☐ |
| Live inventory | WS01, WS02 (real facts from the lab) | ☐ |
| Fleet analysis | `data/synthetic-fleet.csv` — **SYNTHETIC**, 150 invented devices, seed 42 | ☐ |
| Classification output | `data/synthetic-fleet-summary.md` produced by the generator | ☐ |
| Cost options | Three options (upgrade / ESU bridge / do nothing) with risks, not quotes | ☐ |
| Vendor prices | To be filled from a current local quote, with the quote date recorded | ☐ |
| Upgrade runbook | `docs/runbooks/upgrade-win10-to-win11.md` | ☐ |

## 8. Evidence index (designed)

| File (in `evidence/public/`) | What it proves | Verified |
|---|---|---|
| `p04-architecture.svg` | The policy flow and control areas | ☐ |
| `p04-ph0-endpoint-baseline-result.csv` | The "before" endpoint state | ☐ |
| `p04-ph0-hardeningkitty-score-before.*` | The "before" CIS/Microsoft score | ☐ |
| `p04-ph1-baseline-gpo-applied.*` | The baseline reached the pilot client | ☐ |
| `p04-ph1-policy-analyzer-diff.*` | Conflicts with the P1–P3 GPOs, documented | ☐ |
| `p04-ph2-asr-audit-events.*` | Event 1122 audit evidence (7 days) | ☐ |
| `p04-ph2-asr-block-result.csv` | The rules are blocking | ☐ |
| `p04-ph2-eicar-blocked.*` | A test trigger was actually stopped | ☐ |
| `p04-ph3-bitlocker-escrow-result.csv` | Encryption state and escrow result (no keys) | ☐ |
| `p04-ph3-bitlocker-recovery-test.*` | The recovery procedure works | ☐ |
| `p04-ph4-localadmin-before-after.csv` | Local admins before and after | ☐ |
| `p04-ph5-endpoint-compliance.*` | The compliance report | ☐ |
| `p04-ph6-win11-readiness.*` | The synthetic-fleet counts (labelled synthetic) | ☐ |
| `p04-ph0-hardeningkitty-score-after.*` | The "after" score, same method as the "before" | ☐ |

## 9. Data provenance

| Source | Real or synthetic | How it is labelled |
|---|---|---|
| WS01/WS02 facts, BitLocker state, ASR events, compliance report | **Real**, from lab runs | "Source" column in `README.md` points at the evidence file |
| HardeningKitty / CIS-CAT score | **Real**, from a lab run | Score quoted with the tool and list version |
| `data/synthetic-fleet.csv` and every count from it | **Synthetic** | Labelled in the CSV header comment, `data/README.md`, `synthetic-fleet-summary.md`, the business report and the showcase page |
| Cost figures in the readiness report | **Planning figures** | Stated as plan figures with the quote date required before issue |

## 10. Known gaps and exceptions

| Item | Note |
|---|---|
| Tamper protection | On by default and toggled in Windows Security, but central management requires Intune/MDE, which this lab does not have. Recorded as a gap rather than claimed as covered. |
| Intune / Endpoint Privilege Management | Named as the future state for app elevation and as a second escrow target. Not delivered. |
| Entra ID BitLocker escrow | Not used; AD DS escrow is the design. A licensed hybrid environment would normally use both. |
| AppLocker | Audit mode only. No enforced allow-list, because no signed line-of-business package exists yet. |
| Servers | Not hardened by this project. Servers are covered by P1's GPO baseline and later projects. |
| Update rings | Deliberately left to P5 to avoid two projects fighting over the same policy setting. See `scripts/10-UpdateRingsHandoffToP5.sh`. |
| Synthetic fleet | The lab cannot produce a real fleet census. The readiness numbers are a planning exercise over invented data and are labelled as such everywhere. |
| Recovery-key audit log | Retrieval is logged through AD object access auditing; setting that up in full is a P7 logging task, so only the basics are in place here. |
