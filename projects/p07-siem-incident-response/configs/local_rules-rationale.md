# P7 — Custom detection rules: rationale

**File:** `configs/local_rules.xml` (16 rules, `100100`-`100116`) · **Applies to:** SIEM01 /
Wazuh manager · **Project:** P7, fictional Halden Distribution Ltd.

> **Status: designed, not validated.** These rules have not been run against live telemetry.
> Every rule below has an empty validation state; `configs/detection-coverage-matrix.csv` carries
> the result column and it stays blank until an approved simulation (`scripts/07`) and the
> validation report (`scripts/08`) have actually run. Nothing here is a claim of coverage.

## 1. Why behaviour, not signatures

A signature matches a known bad string; a behaviour rule matches *what an action does* to a host
or an identity. Halden is small, so there is no threat-intel feed to keep a signature set fresh;
what it does have is a stable baseline of how many accounts, hosts and services there are
supposed to be. The 16 rules below are written against that baseline:

- **Identity first.** Credential abuse is the most common initial access vector in the market data
  behind this project (`docs/plan/00-research-and-selection.md`), so D1-D4 and D10-D11 watch the
  directory rather than the endpoint.
- **The ransomware window.** Ransomware spends days escalating privilege before it encrypts
  (plan §1). D5 (LSASS), D11 (DCSync), D7 (shadow-copy deletion) and D14 (backup failure) are the
  four detections that sit inside that window.
- **Narrow where the noise is.** Every rule that is expected to be loud in a lab (new services,
  scheduled tasks, Defender blocks) is kept at a *lower* level and tuned with narrow exceptions,
  never by disabling the rule (plan Phase 4, `docs/tuning-log.md`).

## 2. Rule-by-rule rationale

| Rule | Detection | Level | ATT&CK | Why this is worth an analyst's time | Runbook |
|---|---|---|---|---|---|
| 100100 | D1 — member added to a privileged group | 12 | T1098 | The shortest path to domain takeover; the legitimate sources (JML, change record) are known | `privileged-group-change.md` |
| 100101 | D1 context (child, level 0) | 0 | — | Captures the acting account for scoping without re-alerting | `privileged-group-change.md` |
| 100102 | D2 — Kerberos RC4 service ticket | 12 | T1558.003 | RC4 was removed where possible in P3, so any hit is genuinely suspicious | `suspicious-logon.md` |
| 100103 | D3 — TGT without pre-authentication | 10 | T1558.004 | AS-REP roasting; rare in a healthy domain | `suspicious-logon.md` |
| 100104 | D5 — process accessed LSASS | 13 | T1003.001 | LSASS access is credential theft in progress; only a few signed processes should do it | `ransomware-pre-encryption.md` |
| 100105 | D11 — DCSync replication right used | 14 | T1003.006 | Only DCs replicate; anything else is a domain-dump attempt | `privileged-group-change.md` |
| 100106 | D6 — encoded / download-cradle PowerShell | 12 | T1059.001 | Living-off-the-land execution; the usual delivery step after initial access | `ransomware-pre-encryption.md` |
| 100107 | D7 — shadow copy / recovery deletion | 14 | T1490 | The last step before encryption; the highest-value alert in the set | `ransomware-pre-encryption.md` |
| 100108 | D8 — security event log cleared | 12 | T1070.001 | Attackers clear logs to hide the rest; almost always deliberate | `privileged-group-change.md` |
| 100109 | D9 — new Windows service installed | 10 | T1543.003 | Common persistence/execution; loud on workstations, meaningful on servers | `ransomware-pre-encryption.md` |
| 100110 | D9b — scheduled task created | 10 | T1053.005 | Same as above; pairs with D9 when both fire on one host | `ransomware-pre-encryption.md` |
| 100111 | D10 — Tier 0 / break-glass interactive logon | 10 | T1078 | A break-glass account appearing where it should not is an emergency | `privileged-group-change.md` |
| 100112 | D4 — password spraying | 12 | T1110.003 | One source, many accounts, short window — lockout-driven denial and a common first step | `suspicious-logon.md` |
| 100113 | D12 — remote-access (VPN) logon anomaly | 10 | T1133 | Remote access is the perimeter; off-hours or unexpected region deserves triage | `suspicious-logon.md` |
| 100114 | D13 — Defender / ASR blocked an action | 10 | T1204.002 | A block is a prevention, but repeated blocks are an intrusion being contained | `ransomware-pre-encryption.md` |
| 100115 | D14 — backup job failed | 12 | *availability* | Backups are the recovery control for ransomware; a failure removes the safety net | `incident-response.md` |
| 100116 | D15 — agent stopped reporting | 8 | *availability* | A host that goes silent may be the host that was compromised | `restore-wazuh-component.md` |

Coverage summary: **16 rules; 14 mapped to 14 MITRE ATT&CK techniques; 2 availability checks**
(D14, D15) which are deliberately *not* forced into an ATT&CK technique because they are not
attacker behaviour.

## 3. Correlation and escalation

| Situation | Rules that combine | Escalation |
|---|---|---|
| Multiple identity detections on one host/account within an hour | D1 + D10 + D11 | SEV1 — treat as an active domain compromise, page the on-call analyst |
| Credential access followed by execution | D5 + D6 / D7 | SEV1 — assume the attacker has credentials and is staging ransomware |
| Lone low-level detection | D9, D9b, D13 | SEV3 unless it repeats; daily digest |
| Availability | D14, D15 | SEV2 if production, SEV3 if a test host |

Severity levels, response targets and who to notify are in `configs/alert-severity-triage.csv` and
`configs/escalation-oncall-matrix.csv`.

## 4. Testing method (before any rule is trusted)

1. `wazuh-logtest` on SIEM01 with a captured sample event for each rule (from the lab, not
   invented). A rule that does not fire on its own sample is fixed, not shipped.
2. The approved simulation (`scripts/07`) exercises the behaviours in a snapshotted lab.
3. `scripts/08` reports which rule IDs actually fired; `scripts/11` rolls that into the coverage
   report. Until then, the matrix's `validated` column is empty.
