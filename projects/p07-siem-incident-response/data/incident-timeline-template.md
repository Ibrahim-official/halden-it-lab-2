# Incident timeline template — Halden Distribution Ltd.

> **Template. Empty by design.** This is the sheet an analyst fills **during and after** an
> incident to build the timeline that becomes the incident report (plan Phase 6.3) and feeds the
> monthly security summary (`business/p07-exec-brief.md`, P10). It must be completed from real
> Wazuh events and real notes — never invented (AGENTS.md R2). One row per event, in order.

**Incident ID:** `INC-YYYY-NNN` · **Severity:** SEV__ · **Declared by:** ______ · **Date (UTC):** ______
**Short title:** ______________________________ · **Playbook used:** ______________________________
**Status:** open / contained / eradicated / recovered / closed

## Timeline (most important section — timestamp everything in UTC)

| Time (UTC) | Actor | Event / observation | Source (rule id / host / log) | Action taken |
|---|---|---|---|---|
|  | detection | Alert `______` fired | Wazuh rule ______ |  |
|  | analyst | Initial triage began | — |  |
|  | analyst | Severity set to SEV__ | — | Notified ______ |
|  | analyst | Containment step | — |  |
|  | system |  |  |  |
|  | analyst | Eradication step | — |  |
|  | analyst | Recovery step | — |  |
|  | analyst | Incident closed | — | Post-incident review booked |

## 1. What happened (plain language, 3-5 sentences)

_(Written for a non-technical reader: what was affected, what the impact was, what put it right.)_

## 2. Scope and impact

| Question | Answer |
|---|---|
| Which hosts/accounts were involved? |  |
| What data or services were affected? |  |
| Was any data exfiltrated? (how do you know?) |  |
| Was any data encrypted or destroyed? |  |
| Business impact (duration, users, revenue) |  |

## 3. Evidence preserved (chain of custody)

| Item | Where held | Collected by | Hash / note |
|---|---|---|---|
| Wazuh alert export (sanitized) |  |  |  |
| Host memory image *(if captured)* |  |  |  |
| Affected log excerpts |  |  |  |
| Screenshots |  |  |  |

> Raw Wazuh archives and alert dumps are never committed to Git and never published
> (AGENTS.md 4.6). Only sanitized extracts go to `evidence/public/`.

## 4. Root cause

_(The actual technical cause — one paragraph. If unknown, say "unknown" and record what would
determine it.)_

## 5. Detection and response quality

| Question | Answer |
|---|---|
| How was it detected? (rule id) |  |
| Time from first evidence to alert |  |
| Time from alert to containment |  |
| Could it have been detected earlier? How? |  |

## 6. Lessons learned and actions

| Action | Owner | Due | Tracked in | Status |
|---|---|---|---|---|
|  |  |  | P10 change log |  |

**Post-incident review date:** ______ · **Attendees:** ______ · **Report author:** ______
