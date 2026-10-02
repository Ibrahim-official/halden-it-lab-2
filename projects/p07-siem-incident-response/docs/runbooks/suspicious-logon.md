# Runbook — Suspicious logon alert

**Applies to:** any host · **Severity:** depends on the alert (see below) · **Owner:** on-call analyst
**Detections covered:** D2 (100102 Kerberoasting), D3 (100103 AS-REP roasting), D4 (100112 password
spraying), D12 (100113 VPN anomaly), and any built-in Wazuh logon alert.
**Target:** decide *real or not* in five minutes, contain if real, and write down what you saw.

## 0. First five minutes

| Question | Where to look | What a healthy answer looks like |
|---|---|---|
| Who is the account? | `win.eventdata.targetUserName` in the alert | A real staff account with a normal role |
| From where? | `win.eventdata.ipAddress` / `srcip` | A lab address, or the user's normal host |
| Which host, which channel? | `win.system.computer`, `win.system.eventID` | The expected DC or workstation |
| Is it in hours and expected? | the change log (P10) and the JML record (P2) | Nothing new, no ticket, no reason |

If the account is a **Tier 0 or break-glass** account and the host is not a DC or the PAW, treat it
as SEV1 immediately — do not wait to finish the rest of the table.

## 1. Triage by detection

| Detection | What it means | First checks |
|---|---|---|
| D4 password spraying | Many failed logons, one source, many accounts | Is one account now locked out? Is the source in the allow-list? Is it a badly-configured service account? |
| D2 Kerberoasting | A service ticket requested with weak RC4 encryption | P3 removed legacy RC4, so confirm the requesting account and the target SPN; is this a legitimate legacy app? |
| D3 AS-REP roasting | A TGT requested without pre-authentication | Find the account with pre-auth disabled (there should be none — report it if found) |
| D12 VPN anomaly | An off-hours or unexpected-region remote session | Confirm with the user out-of-band; check for a stolen credential |

## 2. Contain (only if it is real)

1. **Lock the account, do not delete it** — `Disable-ADAccount -Identity <user>` — preserves evidence
   and is reversible.
2. If a host is involved, isolate it from the network (VLAN change or Defender quarantine) rather
   than powering it off. Powering off loses memory; ask before doing it.
3. If a source IP is spraying, add a temporary block **with a timeout** and an allow-list covering
   management, so you do not lock yourself out.
4. **Do not change passwords yet** on a domain controller you suspect is compromised — that can
   destroy evidence. Contain first, preserve second, clean third.

## 3. Preserve evidence (before cleaning up)

- Export the relevant Wazuh alerts (sanitized later with `scripts/09`).
- Note the exact timeline: first failure, lockout, successful logon if any.
- If a host is involved and it matters, capture memory using the documented method; otherwise at
  minimum capture the Security/Sysmon logs.
- Write the incident timeline now, from the events, not from memory (`data/incident-timeline-template.md`).

## 4. Eradicate and recover

- Remove any persistence the attacker added (new accounts, group memberships, scheduled tasks,
  services) — check D9/D9b/D1 alerts for the same window.
- Re-enable the account only after a password reset and MFA check (P2).
- Restore any changed data from backup if needed (P8).

## 5. Close out

- Update the incident timeline and the incident report.
- If the detection was noisy, add a **narrow** exception to `docs/tuning-log.md` — never disable the
  rule.
- If the alert was a false positive because the data source was wrong, fix the source, not the rule.

## Rollback

Account disable is reversed with `Enable-ADAccount` after a reset. A temporary IP block is reversed
by removing the firewall rule (it also expires on its own). A host isolation is reversed by returning
it to its VLAN.

> **Privacy note:** monitoring is for security, not for watching staff. If an investigation touches a
> person's activity, it is logged with a reason and restricted to IT (see
> `business/p07-monitoring-policy.md`).
