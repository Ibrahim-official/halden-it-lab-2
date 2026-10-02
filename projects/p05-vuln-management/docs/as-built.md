# P5 as-built — Halden Distribution Ltd. patch and vulnerability management

> **Status: build kit complete, lab execution pending.** This document records the *designed*
> configuration from [`00-design.md`](./00-design.md) and is written so that the *measured* facts
> can be pasted straight in. Nothing in this file is presented as a captured result: the
> **Verified** column stays empty until the matching phase has actually been run in the lab and its
> output sanitised into `evidence/public/`.
>
> **How to finish this document:** run the phase, capture the output, sanitise it (per AGENTS.md
> 4.6) and replace the designed value with the measured one, ticking **Verified**. Evidence files
> go in `evidence/public/` with names like `p05-ph3-scan-summary-result.png`. Any number that was
> not measured stays "not measured".

## 1. Environment summary

| Item | Designed value | Verified |
|---|---|---|
| Domain | `ad.halden.internal` | ☐ |
| Scanner host | LNX01 (Ubuntu Server 24.04), Greenbone CE in Docker | ☐ |
| Scanner management access | web UI on 127.0.0.1:9392, reached by SSH tunnel only | ☐ |
| WSUS host | Member server (OPS01 or FS01), WID database, content on a separate volume | ☐ |
| Scan schedule | Weekly, Sunday 02:00, "Full and fast"; monthly verification after patching | ☐ |
| Lab scope enforced | 192.168.10.0/24, 192.168.20.0/24, 192.168.30.0/24 only | ☐ |

## 2. Scan scope and credentials *(designed)*

| Target set | Hosts | Discovered count | Verified |
|---|---|---|---|
| `servers` | DC01, DC02, FS01, LNX01, OPS01, SIEM01, BKP01 | not measured | ☐ |
| `network` | FW01 | not measured | ☐ |
| `workstations` | WS01, WS02 | not measured | ☐ |
| `warehouse` | FW02 (added in P6) | not measured | ☐ |

Credential model: a dedicated `scanner` SSH user on Linux (no sudo, no privileges beyond reading
package versions) with a key pair held only on LNX01; a dedicated `svc-vulnscan` domain account on
Windows, member of a restricted group, denied interactive logon and RDP, with its password in the
password manager. **Why authenticated:** an authenticated scan can read installed package and patch
versions directly; an unauthenticated scan can only guess from banners. The plan states authenticated
scans find roughly 5–10× more — that factor is a documented expectation, and the actual difference in
this lab is a metric to measure, not to assume.

## 3. Prioritisation model *(designed)*

| Item | Value |
|---|---|
| Tier rules | P0 KEV+exposed (3 d) · P1 KEV or exposed EPSS ≥ 0.5 (7 d) · P2 EPSS ≥ 0.1 or CVSS ≥ 9 on criticality 3 (30 d) · P3 CVSS ≥ 7 (60 d) · P4 everything else (180 d) |
| Score weights | KEV 40 · EPSS 25 · exposure 15 · CVSS 12 · criticality 8 · ransomware 5 (capped at 100) |
| Deduplication key | host + CVE (or title) + service + port |
| Inputs | scanner export, asset-criticality inventory, KEV+EPSS cache |
| Outputs | `reports/prioritized-work-list.csv` / `.json`, browser bundle `demo/sample-findings.json` |
| Unit tests | `scripts/tests/test_prioritize.py` — 26 tests over the pure scoring core (34 expectations after the fix) |

**Sample-run result (synthetic data, not a lab measurement):** over the bundled sample of 51 rows
the model produces 49 unique findings and 9 urgent (P0+P1) items. This is quoted in `README.md` and
`data/README.md` **as a property of the sample dataset**, and it is reproduced by the unit tests.
It is not evidence about the lab.

## 4. Patch rings *(designed)*

| Ring | Group | Deadline | Approval | Verified |
|---|---|---|---|---|
| Ring0-Pilot | `WS11-Pilot` (2 workstations) | 2 days | Automatic for security/critical | ☐ |
| Ring1-Broad | `WS11-Broad` | 5 days (3-day deferral) | Manual after pilot gate | ☐ |
| Ring2-Servers | `Windows-Servers` | 14 days (7-day deferral) | Manual after both workstation rings | ☐ |

Domain controllers are patched outside the rings, in order **DC02 then DC01**, each with pre-checks
(pending reboot, free space) and post-checks (`dcdiag`, services, replication). Linux uses
`13-patch-linux.yml` with `serial: 1` and post-checks; `unattended-upgrades` covers security updates
between cycles. **Patch compliance percentage: not measured.**

## 5. Feeds and data handling *(designed)*

| Source | Use | Handling |
|---|---|---|
| CISA KEV catalogue | "is it known-exploited?" | Fetched by `05-prioritize.py fetch-feeds`, cached locally; in the build kit exercised against a labelled synthetic stand-in |
| FIRST EPSS API | exploit probability | Batched 100 CVEs per request, cached with KEV in one JSON file |
| P9 asset CMDB | exposure and criticality | Until P9 exists, maintained by hand in `configs/p05-asset-criticality.csv` |
| Scanner export | the findings | Greenbone CSV, column-mapped to the lab shape; raw XML archived in `evidence/raw/` |

No API token, scanner password or scan credential is stored in this repository. The Greenbone admin
password is generated on the host and shown once; the GLPI tokens are read from the environment.

## 6. Closure and verification *(designed)*

| Step | Tool | Verified |
|---|---|---|
| Ticket created per P0/P1 item | `06-create-tickets.sh` (GLPI REST) | ☐ |
| Remediation applied with a change record | `business/p05-change-record.md` pattern | ☐ |
| Verification rescan | `03-schedule-scan.sh` monthly task | ☐ |
| Closure report (closed / open / new) | `07-verify-closure.sh` → `evidence/public/` | ☐ |
| MTTR derived from the two work lists | `07-verify-closure.sh` output | ☐ |

**A ticket is closed only when the rescan no longer reports the finding.** MTTR is derived from the
two work lists, never estimated.

## 7. Known gaps and exceptions *(designed)*

| Item | Note |
|---|---|
| WSUS is deprecated | Microsoft announced WSUS deprecation in 2024; it still works and is in-box, so it is used here. The stated future state is Windows Autopatch / Intune or Azure Update Manager. Documented rather than hidden. |
| OPNsense firmware update | Requires a config backup first and a rollback plan; the update procedure is a runbook, and the "check for compromise before patching an exposed device" step applies because FW01 is the edge asset. |
| "Internet-exposed" inside the lab | FW01 faces the WAN and LNX01 publishes a service through it *by design*; in the isolated lab nothing is actually reachable from the internet. Exposure drives priority, not real attack surface. |
| Scale | Ten hosts is not a fleet. The method scales; the numbers describe the sample or the lab only. |
| Feeds in CI | The prioritizer runs offline against cached/stand-in data in this build kit; the live feed fetch is documented but has not been run yet. |

## 8. Evidence plan (what each phase must capture)

| Phase | Capture | Evidence name (example) |
|---|---|---|
| 0 | Policy with the tier table and SLA targets | `business/p05-patch-vuln-policy.pdf` |
| 1 | WSUS groups, GPO client-side targeting, ring membership | `p05-ph1-wsus-rings-result.png` |
| 2 | Ansible run output and per-host report | `p05-ph2-ansible-patch-result.txt` |
| 3 | Greenbone scan summary and target scope | `p05-ph3-scan-summary-result.png` |
| 4 | Prioritised work list excerpt, funnel, tier distribution | `p05-ph4-prioritized-funnel-result.png` |
| 5 | Rescan showing closure; exception register example | `p05-ph5-rescan-closure-result.png` |

> Placeholder names only: these files do not exist until the phase runs. Anything published on the
> portfolio is filled from the real capture, sanitised per AGENTS.md 4.6.
