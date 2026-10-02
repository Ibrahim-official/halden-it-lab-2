# Change record — P1 Core Infrastructure Build

> Retroactive change record, written to the standard Halden uses for every change (feeds the
> change log and the P10 governance dashboard). In a small company the same person often proposes
> and approves; that separation is documented honestly rather than pretended.

| Field | Value |
|---|---|
| **Change ID** | CHG-2026-001 |
| **Title** | P1 — Core infrastructure build: AD DS, DNS, DHCP, file services, GPO baseline, Linux integration |
| **Raised by** | IT (Muhammad Ibrahim Akmal) |
| **Approved by** | Managing Director *(business owner of the fictional Halden; see note on the lab)* |
| **Date raised** | 2026-09-29 |
| **Planned implementation** | 2026-10-02 onwards, phase by phase (Phase 0 → Phase 8) |
| **Category / risk** | Infrastructure — High risk (Tier 0: authentication, DNS, DHCP) |
| **Affected services** | Logon, DNS, DHCP, all file shares, Group Policy, Linux SSH access |
| **Affected systems** | HOST01 (Hyper-V), FW01, DC01, DC02, FS01, LNX01, WS01, WS02 |

## 1. Description of the change

Replace the single aging server with a redundant, documented Windows Server 2025 foundation:
two replicating domain controllers with AD-integrated DNS, a DHCP failover pair, a dedicated file
server with DFS namespace, access-based enumeration, FSRM quotas and file screens and shadow
copies, a tiered Group Policy baseline, and one Ubuntu server joined to the domain with
group-controlled SSH and sudo. All of it is created by idempotent, logged scripts kept in the
repository, plus an as-built document, a permission matrix and user runbooks.

## 2. Reason for the change

The current single server is a single point of failure for logon, addressing and files, and all
85 staff hold Full Control on the shared drive so a single mistake or a ransomware infection can
destroy any department's data. There is also no written answer to "who can read Finance data" and
no self-service file restore. The change removes the single point of failure, applies least
privilege by role, and produces the documentation and evidence that the business currently lacks.

## 3. Impact and risk

| Area | Impact | Mitigation |
|---|---|---|
| Users | New drive letters appear; a screen lock is enforced; folders that a user has no right to open are hidden | 1-page brief to all staff in advance; Service Desk briefed; ticket route for missing access |
| Logon / DNS / DHCP | Outage would stop the whole company | Work done out of hours, phase by phase; DC02 and DHCP failover tested by powering DC01 off |
| Data | New permission model could lock a user out of a folder they need | Access approved by department heads first; permission matrix kept; Administrators retain recovery access |
| Access control | A mistake could grant too much access | Only `DL_` groups ever appear on ACLs; automated ACL audit must report **0 violations** |

## 4. Implementation plan (phases)

| Phase | Work | Window | Verification |
|---|---|---|---|
| 0 | Design document (IP plan, naming, OU tree, DNS/DHCP design) | 2026-10-02 | Design reviewed against the plan |
| 1 | DC01 promoted; DNS zones, forwarders, scavenging, time source | Out of hours | `dcdiag /q` clean; DNS records resolve |
| 2 | DC02 promoted; sites/subnets; replication verified | Out of hours | `repadmin /replsummary` 0 fails |
| 3 | DHCP scope, options, 50/50 failover, name protection | Out of hours | Failover state Normal; client renews with DC01 off |
| 4 | OU tree, AGDLP groups, 85 users imported from CSV | Out of hours | Import log; idempotent second run |
| 5 | FS01 shares, ACLs, DFS-N, ABE, FSRM, shadow copies | Out of hours | ACL audit 0 violations |
| 6 | GPO baseline + Central Store + GPO backup | Out of hours | `gpresult /h` on WS01 |
| 7 | LNX01 joined; AD-based SSH and sudo | Out of hours | Denied for non-members; sudo for members |
| 8 | As-built doc, diagram, runbooks | Same evening | Documents produced from live output |

## 5. Test plan (acceptance)

1. Power off DC01 — logons, DNS resolution and DHCP leases continue via DC02.
2. Finance user opens the company share — the HR folder is not visible.
3. Sales user copies an `.exe` into the Sales share — blocked by the file screen.
4. Delete a file — restore it through "Previous Versions" without IT.
5. Non-IT domain user connects to LNX01 by SSH — denied.
6. Re-run the user import script — no duplicates, no errors (idempotent).

## 6. Backout plan

Each phase is snapshotted before it runs (`snap-p1-ph<N>-before`). Backout for any phase is to
power off the affected VM, revert the snapshot and re-run the previous phase's scripts, which are
idempotent. Domain controllers are fixed forward where possible: reverting a DC snapshot can
disturb replication, so it is only used as a last resort and is recorded in `DECISIONS.md`.

## 7. Post-implementation review

To be completed when the last phase is verified: actual completion date, acceptance test results,
anything that went wrong, and whether any phase overran. Results are recorded in
`projects/p01-core-infrastructure/README.md` with a source file for every number.

> Note: this is a home-lab change record for a fictional company (Halden Distribution Ltd.). The
> technical content, scripts and test results are real; the business approval line represents the
> lab owner's decision, not a real customer sign-off.
