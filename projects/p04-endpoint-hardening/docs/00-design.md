# P4 — Phase 0: Design document (design before you build)

**Project:** P4 Endpoint Hardening Baseline and Windows 11 Readiness Program
**Company:** Halden Distribution Ltd. (fictional, 85 staff) · **Domain:** `ad.halden.internal`
**Status:** Phase 0 complete (design) · **Owner:** Muhammad Ibrahim Akmal · **Mode:** A (Advisor)
**Spec:** [`docs/plan/P04-endpoint-hardening-win11-readiness.md`](../../../docs/plan/P04-endpoint-hardening-win11-readiness.md)
**Depends on:** P1 (GPO structure and the `WKS - Security Baseline - v1` placeholder), P3 (Windows LAPS and privileged-access tiering)

> Why design first: endpoint hardening is the project most likely to break the business. A baseline
> that is too strict stops a warehouse scanner; an ASR rule enforced too early blocks Finance's
> month-end macro; BitLocker enabled without escrow locks a user out of their own laptop with the
> key in nobody's hands. Each of those is a decision, and this document records the decisions
> before any of them is made in the lab.

---

## 1. Goal and scope

Turn "the PC as it came out of the box" into a measured, supportable endpoint standard, and answer
the Windows 10 end-of-support question for management with numbers and costs.

Success is the measurable criteria in the P4 plan:

- Baseline compliance raised from a measured "before" to **at least 90%** on Windows 11 clients
- **16 or more** Defender ASR rules audited for at least 7 days, then moved to Block, with only
  documented exceptions
- **BitLocker (XTS-AES 256, TPM)** on 100% of clients, recovery keys escrowed to AD, retrieval tested
- **0 standard users with local admin rights**, verified by script
- A daily **compliance report** (HTML + CSV) across nine named controls
- A Windows 11 readiness report with fleet counts and a **costed three-option recommendation**

**In scope:** Windows 11 clients WS01 and WS02; the baseline GPOs; Defender and ASR; BitLocker and
escrow; local admin removal; firewall, Credential Guard, LSA protection and PowerShell logging; the
compliance report; the readiness assessment; and one in-place Windows 10 → 11 upgrade runbook.

**Out of scope:** WSUS update rings and vulnerability scanning (P5); VLAN-level firewall enforcement
(P6, which narrows the management-subnet rules designed here); SIEM ingestion of the Defender and
PowerShell events (P7, which consumes them); the CMDB records (P9). Server hardening is out of scope:
this project is the endpoint standard.

## 2. Business context (why this exists)

Halden's PCs were set up by whoever unboxed them. Users are local admins, so they can (and do)
install anything and switch off whatever protection gets in the way. BitLocker is off, so a lost
sales laptop is a reportable data breach. Defender runs on defaults only, so the behaviour that
ransomware relies on — macro abuse, script execution, credential dumping — is not blocked. About 30%
of devices still run Windows 10, which lost support on 14 October 2025, and nobody has told the
business what replacing or upgrading them would cost.

**Market evidence used in the business case** (from `docs/plan/00-research-and-selection.md`):
about **21% of SMB Windows devices still ran Windows 10 in mid-2026** (Lansweeper, reported by
Computer Weekly), and Microsoft's commercial Extended Security Updates run for at most three years
and must be paid for each year. Ransomware appears in **88% of SMB breaches** and usually runs on
endpoints, which is exactly what baseline hardening and ASR rules target.

## 3. Design principles

1. **Measure before and after.** Phase 0 captures the "before" state on WS01. Every claim in the
   README has a file in `evidence/public/` behind it (AGENTS.md R2).
2. **Audit before block.** Every behavioural control — ASR rules first of all — runs in a logging
   mode before it is allowed to stop work. The script enforces the minimum review period in code.
3. **Never edit the vendor.** Microsoft's baseline is imported into a new GPO; Halden deviations go
   into a separate, higher-precedence overrides GPO. The next baseline release can be compared
   rather than merged.
4. **Escrow before encryption.** No BitLocker volume is encrypted until the AD key-escrow policy is
   confirmed in place. The script refuses to run otherwise.
5. **Least privilege on the endpoint.** A local administrator account can disable every other control
   in this document, so removing standing local admin rights is a security control, not a
   convenience question.
6. **One source of truth for every rule.** The readiness rules exist once (`data/fleet_rules.py`), and
   the generator, the analyzer and the tests all use them, so the numbers cannot disagree.

## 4. Threat model (what we are defending against)

Assets: the device itself, the data on it (Finance, HR and Sales files, cached credentials), and the
domain credentials a compromised endpoint can reach.

| # | Threat | Who/what does it | Control in this project | Residual risk |
|---|---|---|---|---|
| T1 | Phishing attachment launches a payload | User opens a document from email; Office macro spawns a shell | ASR rules 1, 2, 3, 4, 7, 14; Defender cloud protection | A user with local admin can still run an unsigned tool they downloaded themselves — reduced by removing local admin |
| T2 | Lost or stolen laptop | Sales laptop left in a car; device resold | BitLocker XTS-AES 256 with TPM, escrowed recovery key | A stolen device with the user's PIN-less session unlocked is still readable while powered on |
| T3 | Ransomware encrypts the device and its shares | Ransomware binary run by a user, or delivered by a macro | ASR ransomware rules 11 and 16; Defender real-time; file screening from P1; backups in P8 | If the account has write access to a share, data on the share is at risk regardless of the endpoint |
| T4 | Credential dumping from LSASS | Malware or an attacker on the device reading memory | ASR rule 8; Credential Guard; LSA protection (RunAsPPL) | Credential Guard depends on hardware (VBS); must be verified, not assumed |
| T5 | User disables a control | A user with local admin turns off Defender to install a game | Local admin removal; tamper protection; compliance report flags the drift | Tamper protection is centrally managed only through Intune/MDE, so in this lab it is set manually and recorded as a gap |
| T6 | Lateral movement with PSExec or WMI | An attacker moving from one endpoint to the domain | ASR rule 9 (audit then deliberate block); firewall inbound block; P6 segmentation | Rule 9 can conflict with management tooling, hence the deliberate audit |
| T7 | Driver-based defence evasion | Vulnerable signed driver loaded to disable protections | ASR rule 13; Secure Boot; Windows 11 driver-signing requirements | Zero-day drivers are out of scope for a baseline |
| T8 | Loss of the recovery key itself | Escrow not in place; key stored only on the device or in a photo | Escrow-before-encryption rule; helpdesk runbook with identity verification and logging | Social engineering against the helpdesk: mitigated by the verification step and the narrow group allowed to retrieve keys |

**The threat this project is most often judged on in an interview is T8**, because it is the one an
auditor looks for: BitLocker on every device with recovery keys that nobody can actually find.

## 5. Why audit before block (the central design decision)

An ASR rule in **Block** mode is a behavioural control that stops an action. An ASR rule in **Audit**
mode logs what it *would* have stopped. Blocking first is the mistake that gives hardening a bad
reputation inside a business:

- Finance runs a month-end macro that spawns a helper process. Rule 2 ("Block Office apps from
  creating child processes") blocks it. The month-end close stops on the Monday morning it is
  enforced, and IT's project is now "the thing that broke reporting".
- The warehouse uses a USB scanning tool with an unsigned component. Rule 10 stops it, and goods
  cannot be booked in.

So the design is:

1. Deploy all 16 rules in **Audit** (value 2) and enable Defender cloud/PUA/network protection.
2. Review **Event ID 1122** (audited) for **at least 7 days**, including a deliberate trigger (an
   EICAR test file and a Microsoft ASR test document) so there is positive proof the rules are
   working and not merely configured.
3. For each rule, decide: block it, keep it in audit with a recorded reason, or add a narrow
   exclusion.
4. Move to **Block** (value 1) and watch **Event ID 1121** afterwards.
5. Record every exception in the ASR exception register with a business owner and an expiry.

The review period is enforced in code: `03-Set-AsrBlock.ps1` refuses to run without at least
`-ReviewedAuditDays 7`, or an explicit `-Force` that has to be justified in the change record. A
control that only exists in a documented intention is not a control.

## 6. Baseline choice and what is deliberately excluded

**Choice:** the **Microsoft Security Baseline for Windows 11**, imported through the Security
Compliance Toolkit, with a **CIS** finding list used for the independent before/after score
(HardeningKitty in audit mode against the CIS Windows 11 Enterprise list, with CIS-CAT Lite as the
alternative if the toolkit is preferred). The Microsoft baseline is the vendor-supported default;
CIS scoring gives a comparable number for the "before → after" claim without either tool being
presented as the other.

**Why not CIS-hardening everything:** a full CIS Level 1 profile includes settings (for example
strict removable-media policy or aggressive credential-caching limits) that conflict with the way
this business actually works. Deviations are therefore explicit.

| Deliberately excluded / deferred | Why (business reason) | Where it is recorded |
|---|---|---|
| Blocking removable storage entirely | Warehouse scanners and USB stock guns are in daily use | `configs/baseline-policy.yaml` |
| TPM + PIN startup for BitLocker | Adds a support call per forgotten PIN; TPM-only for standard devices | `configs/win11-readiness-rules.yaml` |
| Aggressive credential-caching limits | Remote sales staff must log in offline | `configs/baseline-policy.yaml` |
| AppLocker enforcement | No signed line-of-business package yet; audit only, as a stretch goal | `configs/baseline-policy.yaml` |
| ASR rule 9 (PSExec/WMI) moving to block | Can break management tooling | `configs/asr-rules.yaml`, `DECISIONS.md` |
| Update-ring configuration | P5 owns update rings; P4 must not compete for the same setting | `scripts/10-UpdateRingsHandoffToP5.sh` |

There is no "make it like CIS" button at Halden. A deviation that is written down, owned and expiring
is a design decision; one that is discovered later by an auditor is a finding.

## 7. BitLocker escrow and recovery design

**Escrow target:** Active Directory DS, stored as `msFVE-RecoveryInformation` under the computer
object. This is deliberate for a small business: the domain already exists, the keys are recoverable
by IT without another system, and access is controlled by AD permissions rather than by a separate
console. The alternative (Entra ID / Intune) would be the right answer with a paid licence, and is
recorded as a future state rather than pretended into existence.

**Order of operations (the mistake the plan warns about):**

1. Deploy `WKS - BitLocker - v1` with "Store recovery information in AD DS" **and** the delegations
   that let the helpdesk group read it.
2. Verify the policy reached the client (`gpresult`, and a Defender-style settings check).
3. Only then encrypt — `04-Enable-BitLockerEscrow.ps1` refuses without `-EscrowPolicyVerified`.
4. Confirm escrow on a DC: an `msFVE-RecoveryInformation` object exists under the computer.
5. Run the recovery test: force recovery, retrieve the key as a helpdesk user, unlock, and record the
   time taken.

**Recovery is an identity problem, not a technical one.** The technical retrieval is one cmdlet. The
risk is a caller who claims to be a user and asks for a key. The helpdesk runbook therefore requires
identity verification before release, restricts retrieval to a small group, and logs who read which
key. That logging is the control an interviewer is looking for.

**Key handling rules (R3):** recovery keys are never written to the repository, never pasted into
chat, and never shown in a screenshot. The evidence script writes a CSV containing the **key
protector ID** and the escrow result only. Any screenshot of the AD escrow check is cropped to remove
the password column.

## 8. Design of the local-admin removal

The local `Administrators` group ends with:

- the built-in `Administrator` account, whose password is managed by **Windows LAPS** (delivered by
  P3), and
- `G_Tier2_Admins` (the server/endpoint admin tier from P3).

`Domain Users`, named individuals and vendor accounts are removed. Delivered as a Group Policy
Preferences *Local Users and Groups* item with "delete all member users/groups" so that a machine
that drifts is corrected at the next policy refresh; applied directly on the clients in the lab so
the acceptance test can actually be run.

The "I need admin for one app" request is answered in `business/p04-user-comms.md`:

1. Package the application and deploy it — the user does not need rights, the installer does.
2. If that is impossible, grant a **time-limited** elevation for a named period, with manager
   approval, logged, and automatically expired.
3. Only if both fail, and with a recorded risk acceptance, add the smallest possible exception.

Endpoint Privilege Management (Intune) is named in the standard as the future state; it is not
claimed as delivered, because the licence does not exist in this lab.

## 9. Windows 11 readiness criteria

The rules are in `configs/win11-readiness-rules.yaml` and implemented once in `data/fleet_rules.py`:

| Requirement | Rule | Failure label |
|---|---|---|
| CPU | Intel 8th generation / AMD Zen+ or newer | CPU older than Intel 8th generation / AMD Zen+ |
| TPM | 2.0, present and enabled | TPM 2.0 missing or disabled |
| Firmware | UEFI mode | Legacy BIOS (no UEFI firmware mode) |
| Secure Boot | Capable and enabled | Secure Boot not enabled |
| RAM | 4 GB or more | RAM below 4 GB |
| System disk | 64 GB or more | System disk below 64 GB |

Decision: **any** unmet requirement means `replace`; all met and still on Windows 10 means `upgrade`;
all met and already on Windows 11 means `ready`. The hardware check always runs first, so a device
that was force-upgraded with unsupported hardware is never counted as ready.

**The fleet is synthetic.** The lab has two Windows 11 VMs and one Windows 10 VM — enough to test the
procedure, nowhere near enough to talk about a fleet. `data/synthetic-fleet.csv` is therefore an
**invented** 150-device inventory for the fictional company, clearly labelled synthetic everywhere it
appears. Its counts are a plain count of that file, produced by the generator, and are never
presented as a measurement of real hardware. The *rules* and the *procedure* are real.

## 10. Compliance report design

Nine checks, one HTML traffic-light report and one CSV per day (P4 Phase 5):

| # | Check | Pass condition |
|---|---|---|
| C1 | OS build | At or above the supported Windows 11 release (default minimum build 22631) |
| C2 | BitLocker | OS volume protection On and 100% encrypted |
| C3 | Defender | Real-time on, signatures under 24 hours old, quick scan within 7 days |
| C4 | ASR | Zero rules in audit, at least 16 rules blocking |
| C5 | Firewall | Enabled on all three profiles |
| C6 | Local admins | Approved members only |
| C7 | LAPS | Managed password set within 31 days (read via the update time only) |
| C8 | Pending reboot | No pending reboot |
| C9 | Last patch | A patch installed within 35 days |

The overall figure is passed checks divided by the checks that actually ran. A check that could not
run (for example the LAPS cmdlet is missing before P3 finishes) is shown as **amber "not checked" and
excluded**, never counted as a pass — otherwise a broken script would silently raise the score.

The CSV is the Power BI input for P10, and C9 is the seam with P5: the same report is reused as the
patch-compliance view rather than duplicated.

## 11. Build phases and evidence plan

| Phase | Deliverable | Evidence to capture |
|---|---|---|
| 0 | This design document; the "before" endpoint state | `p04-ph0-endpoint-baseline-result.csv`, HardeningKitty before score |
| 1 | Microsoft baseline imported, overrides GPO, Policy Analyzer comparison, pilot ring | GPO report, Policy Analyzer diff, `gpresult` on WS02 |
| 2 | Defender hardened, 16 ASR rules in audit for 7 days, then block | Event 1122 sample, EICAR/test-document result, Event 1121 after block, ASR state CSV |
| 3 | BitLocker XTS-AES 256 with AD escrow and a tested recovery | Escrow object screenshot (password cropped), recovery test result, time taken |
| 4 | Local admins removed; firewall, Credential Guard, LSA protection, PowerShell logging | Administrators before/after CSV, `msinfo32` VBS status, LAPS status CSV |
| 5 | Daily compliance report | `endpoint-compliance-<date>.html` + CSV, overall % |
| 6 | Windows 11 readiness assessment and a Win10 → 11 upgrade runbook | Readiness charts (synthetic fleet, labelled), upgrade-runbook walkthrough |
| 7 | README, showcase page, business artefacts | Sanitized copies in `evidence/public/` |

## 12. Snapshot and rollback plan

- **Before every phase:** a hypervisor snapshot of each VM the phase touches, named
  `snap-p4-ph<N>-before`. Rollback = revert that snapshot and re-run the previous phase, whose
  scripts are idempotent.
- **GPO changes** are backed up by `01-Import-SecurityBaseline.ps1`; rollback is unlink then delete
  the GPO (`Remove-GPLink`, `Remove-GPO`).
- **ASR changes** roll back with `03-Set-AsrBlock.ps1 -RevertToAudit`.
- **BitLocker** rolls back with `Disable-BitLocker` while the key is still escrowed — never by
  deleting the escrow record, because a device that can still boot with no key anywhere is worse than
  an unencrypted one.
- **Local admin removal** rolls back by re-adding the affected membership.
- Phase 0 changes nothing, so no snapshot is needed for it. **Phase 1 onwards does.**

## 13. Risks

| Risk | Mitigation |
|---|---|
| ASR block breaks a business application | Audit mode for 7 days minimum, enforced in the script; narrow exclusions only; rollback one command away |
| BitLocker enabled before escrow exists | Escrow-before-encryption enforced in `04-Enable-BitLockerEscrow.ps1`; key state verified from a DC |
| Editing the Microsoft baseline makes the next baseline upgrade painful | Baseline imported into a new GPO; Halden deviations in a separate overrides GPO |
| Local admin removal blocks a legitimate task | Exception process with time-limited elevation; user comms written before the change |
| Tamper protection cannot be centrally managed without Intune | Documented as a known gap in `docs/as-built.md` §10, not claimed as covered |
| The synthetic fleet is mistaken for a real inventory | Labelled synthetic in the CSV header, the data README, the readiness summary, the report and the showcase page |
| Evaluation licence expiry (Windows 11 eval is 90 days) | Tracked in `PROGRESS.md`; do the ASR and BitLocker work early in the window |

## 14. Decisions taken

1. **Microsoft baseline as the base, CIS finding list as the score.** Vendor-supported defaults are
   easier to defend in a small business; the CIS list gives an independent percentage.
2. **AD escrow, not Entra ID.** No licence for Intune/MDE; the domain already exists and the
   delegations are the control. Future state recorded.
3. **16 ASR rules, audit then block, rule 9 reviewed deliberately.** Chosen against the plan's list;
   GUIDs to be re-verified against Microsoft Learn at execution time.
4. **The readiness fleet stays synthetic and stays labelled.** The lab cannot produce a real fleet
   census, and inventing one silently would be a lie about evidence.
5. **No `metrics:` block on the showcase page until real results exist.** The page says "not
   measured" rather than showing a plausible score.

## 15. Interview notes (phase 0)

**"How do you deploy ASR without breaking the business?"** Audit mode first, for a defined period,
with a deliberate test trigger so you know the rules fire. Review the audited events by rule and by
department, then block; keep a register of exclusions with an owner and an expiry; pilot one ring
before the fleet; and make the rollback a single command, because the day you need it is not the day
to be writing it.

**"A user needs admin rights to install software."** Understand the actual need first. Usually the
answer is packaging the application and deploying it, so the user never needs rights. If it is
genuinely a one-off, a time-limited elevation with manager approval and logging is defensible.
Permanent local admin as a convenience is not, because local admin can switch off every other control
in the standard.

**"Why does a missing BitLocker escrow matter if the disk is encrypted?"** Because encryption without
a recoverable key converts a hardware fault into permanent data loss, and a lost key is discovered at
the worst moment — when the device will not boot. An auditor looks for the escrow, the delegations and
a tested retrieval, not just for the encryption state.

---

*Next step: Phase 1 — snapshot the clients and DC01 (`snap-p4-ph1-before`), then import the Microsoft
baseline into a new GPO and link it to the pilot OU. Mode A: the owner runs the commands and pastes
the output back.*
