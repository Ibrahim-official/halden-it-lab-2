# Runbook — Triage a new critical finding

**Applies to:** any finding tiered P1 or above · **Duty:** IT / Systems · **Time:** 30 min
**Trigger:** the weekly scan finishes, or the scanner raises an alert on a KEV finding.

## Why this runbook exists

A tier from the prioritizer is a **first pass**, not a verdict. The model knows the CVE, the EPSS
probability, whether the asset is exposed and how critical it is. It does **not** know whether the
service in question is actually running, whether the port is reachable, or whether a compensating
control already blocks the path. Triaging is where a human checks those things before the team
spends an evening patching something that does not matter — or ignores something that does.

## 0. First 10 minutes — establish what you have

```bash
cd projects/p05-vuln-management
python3 scripts/05-prioritize.py explain \
  --findings data/scans/latest.csv \
  --assets   configs/p05-asset-criticality.csv \
  --enrichment data/kev-epss-cache.json \
  --rules    configs/p05-tier-rules.yml \
  --cve      CVE-XXXX-XXXXX --host <host>
```

That prints the tier, the score, the *reasons* (KEV, exposure, EPSS, CVSS, criticality) and the
recommended fix. Read the reasons before the CVSS.

## 1. The five questions

| # | Question | How to answer it | If "no" |
|---|---|---|---|
| 1 | Is the vulnerable service actually running on that port? | `ss -tlnp` on Linux; `Get-NetTCPConnection -LocalPort <port>` on Windows | Downgrade: the finding may be a false positive; note it and move on |
| 2 | Is the port reachable from the zone an attacker would be in? | Check the firewall rules (P6 matrix once it exists); from a client: `Test-NetConnection -Port` | Keep the tier, but the compensating control reduces urgency — record it |
| 3 | Is there a KEV entry, and is exploitation automatable? | Re-check the KEV entry (ransomware campaign flag) | KEV P0/P1 keep their tier; a non-KEV item can wait for the cycle |
| 4 | What breaks if this host is down for the window? | Ask the asset owner listed in the work list | If downtime is not approved, plan a compensating control and an exception |
| 5 | Is there already an open ticket or exception for this? | `06-create-tickets.sh --dry-run` (idempotent) and the exception register | — |

## 2. Decide, and write the decision down

Pick exactly one outcome and record it in the ticket:

| Outcome | When | Next step |
|---|---|---|
| **Fix now** | P0, or a P1 with an easy fix | Raise the change, patch in the next window (or immediately for P0) |
| **Schedule** | P1–P2 that cannot be fixed today | Ticket with the SLA due date; add to the monthly cycle |
| **Compensating control** | Cannot patch yet (legacy app, vendor dependency) | Block the path (firewall/segmentation), then raise an exception with an expiry |
| **Accept** | Business decides the residual risk is tolerable | Management signs the exception register; IT records the control in place |
| **False positive** | Service not running, or not vulnerable at that version | Note why, so the next triage does not repeat the work |

## 3. For a P0 (KEV on an internet-exposed host) — the extra step

**Check for compromise before you patch.** If an attacker is already inside, patching the door does
not remove them (CISA BOD 26-04 makes this explicit). Before patching:

1. Review logs for the affected host for the days since the vulnerability was published
   (`/var/log/auth.log`, Windows Security log, Wazuh alerts once P7 exists).
2. Check for new or unexpected accounts, scheduled tasks and outbound connections.
3. Compare the current config to the last known-good backup (P9 config-as-code).
4. **Then** patch, and re-check after patching that nothing unexpected remains.

If you find signs of compromise, this is an **incident**, not a patch — follow the P7 incident
runbook instead, and keep the evidence before you change anything.

## 4. Close the loop

A finding is not done when it is patched; it is done when a scan says so:

```bash
./scripts/07-verify-closure.sh \
  --before reports/prioritized-work-list-before.csv \
  --after  reports/prioritized-work-list-after.csv \
  --out    evidence/public/p05-verify-closure-result.csv
```

Only the rows marked `closed (no longer reported)` may close their tickets. Everything else stays
open, and the reason is written in the ticket.

## 5. Escalate when

- A P0 cannot be fixed inside 3 days → tell the IT manager and the asset owner the same day.
- The fix needs downtime the business has not approved → the asset owner decides, and the decision
  goes in the change record.
- A finding affects a system that is end-of-life (like the OPNsense firmware being two years old) →
  it becomes an ask in the monthly report: replace or budget, do not patch forever.

> **Lab practice:** tiers and scores describe *this* lab. Scale and trends are not claimed until they
> have been measured over real cycles.
