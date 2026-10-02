# Halden Distribution Ltd. — vendor security advisory log

**Document:** P5-LOG-001 · **Owner:** IT · **Review:** monthly, with the vulnerability report
**Purpose:** to record the vendor security advisories we have reviewed, whether they affect us, what
we did, and when. This is the "coordinate with vendors" part of the job: the scanner cannot see a
firewall firmware advisory or a hardware limitation, so a human tracks them.

> **Home-lab artefact.** The table is a **template with worked-example rows clearly marked**. Nothing
> in it has been reviewed or actioned in the lab; it shows the shape the log takes once it is in use.

## How to use this log

1. Subscribe to the advisory feeds for everything Halden depends on (firewall, operating systems,
   backup software, the service-desk stack).
2. For each advisory that arrives, record it here: vendor, product, advisory id, whether the affected
   version is in use, the action, and the date.
3. If the advisory maps to a scanner finding, link the ticket. If the scanner *cannot* see it
   (hardware, firmware, a feature disabled at the port), the log is the only record that it was
   considered.
4. An advisory that affects an end-of-life device becomes an ask in the monthly report: replace,
   isolate, or accept with a control — not "keep patching forever".

## Log

| Date reviewed | Vendor | Product / component | Advisory reference | Affects us? | Action taken | Ticket / change ref | Reviewed by |
|---|---|---|---|---|---|---|---|
| — | — | *(no live entries yet — nothing has been reviewed in the lab)* | — | — | — | — | — |
| **2026-10-02** *(worked example)* | OPNsense | Firewall (FW01) | Vendor security advisory for the current release | **Yes** — the installed release predates the advisory | Back up configuration, then update FW01 in the Saturday window; re-check interfaces, VPN and rules | *(example: CHG-2026-008)* | *(example: IT)* |
| **2026-10-02** *(worked example)* | Microsoft | Windows Server 2025 | Monthly vendor update release | **Yes** — applies to DC01, DC02, FS01 | Servers ring approval after the pilot gate; domain controllers in DC02-then-DC01 order | *(example)* | *(example: IT)* |
| **2026-10-02** *(worked example)* | Distribution maintainer | Ubuntu Server 24.04 | Security update notice for the web/SSH stack | **Yes** — applies to LNX01, OPS01, SIEM01, BKP01 | Ansible patching cycle; unattended security updates cover the gap between cycles | *(example)* | *(example: IT)* |

## Reporting

The monthly vulnerability report states, from this log: advisories reviewed, advisories affecting
Halden, and any end-of-life device that keeps appearing. Those are facts from the log, not estimates.

> **Note:** this log belongs to a home-lab project for a fictional company. No entry here represents
> a real vendor relationship or a real advisory response.
