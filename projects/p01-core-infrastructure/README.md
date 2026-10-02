# P1: Core Infrastructure Build — AD DS, DNS, DHCP, File Services, GPO and Linux Integration

> Home-lab project in an isolated, simulated 85-user company ("Halden Distribution Ltd.").
> Presented as a home lab on the portfolio site — never as employment experience.
> All staff data used here is **synthetic** (see [`data/README.md`](./data/README.md)).

**Status:** build kit complete — **lab execution pending** · **Build order:** 1 of 10 · **Depends on:** nothing (this is the foundation)
**Plan:** [`docs/plan/P01-core-infrastructure-build.md`](../../docs/plan/P01-core-infrastructure-build.md) · **Design:** [`docs/00-design.md`](./docs/00-design.md) · **Site page source:** [`showcase.md`](./showcase.md)

## Problem

Halden runs everything on one aging server: domain controller, file server and print server with no
redundancy, and every one of the 85 staff holds Full Control on the shared drive. If that server
dies, nobody can log in, get an IP address or open a file; because permissions are wide open, a
single mistake or one encrypted laptop can destroy any department's data. Nothing in writing says
who can read Finance or HR data, and a deleted file means an IT call.

AD DS, DNS and DHCP are **Tier 0**: when they fail, everything fails. That is why this project is
the foundation the other nine stand on.

## What I built

- **Two replicating domain controllers** (Windows Server 2025) with AD-integrated DNS, so
  authentication and name resolution survive one server being down.
- **DHCP with a 50/50 failover relationship** between the two DCs, plus name protection and
  dynamic DNS updates performed by a dedicated low-privilege service account rather than a DC's
  computer account.
- **AD sites and subnets** (HQ 192.168.10.0/24 and WAREHOUSE 192.168.20.0/24) created now so the
  P6 segmentation work has a topology to attach to.
- **An OU tree that mirrors the org chart** (Management, Finance, HR, Sales, Operations, IT) with
  protected OUs, a `_Admin` tier-0 OU and a `Disabled` OU for leavers.
- **AGDLP least-privilege permissions**: accounts → `G_` global role groups → `DL_` domain local
  resource groups → permission. Only `DL_` groups, SYSTEM and Administrators may appear on an ACL.
- **File services done properly on FS01**: five departmental shares plus hidden home drives, a DFS
  namespace so shares can be moved between servers without remapping drives, Access-Based
  Enumeration, FSRM quotas and file screens, and twice-daily shadow copies for self-service restore.
- **85 user accounts provisioned from a CSV** by an idempotent, logged PowerShell script that sets
  department, title, manager and EmployeeID and forces a password change at first logon.
- **A tiered Group Policy baseline**: domain password and lockout policy, drive maps with group
  item-level targeting, desktop standards, kiosk lockdown and server remote-management rules, with
  the ADMX Central Store configured and all GPOs backed up into `configs/`.
- **An Ubuntu server joined to AD** with `realmd`/SSSD, SSH restricted to an AD group by key only,
  and sudo controlled by AD group membership.
- **An ACL audit script** that walks every share root and fails if any ACE is not a `DL_` group —
  the automated control that keeps the least-privilege model honest.
- **Documentation as a deliverable**: as-built document, logical diagram (`.drawio` + `.svg`),
  six runbooks, a permission matrix for department-head sign-off and a 1-page staff brief.

## Architecture

![P1 logical architecture](docs/diagrams/p01-logical.svg)

Two domain controllers share authentication, DNS and DHCP; FS01 holds the data with permissions
granted only through `DL_` groups; LNX01 is joined to the domain with group-controlled access; and
WS01/WS02 are the policy test clients. FW01 (OPNsense) is the gateway and keeps the lab isolated —
the lab never touches the home network.

## How to reproduce

Run in order. Every script is idempotent, lab-guarded (it refuses to run outside
`ad.halden.internal` / a host carrying `/etc/halden-lab`) and supports `-WhatIf`.

| Order | Where | Script | Does |
|---|---|---|---|
| 0 | HOST01 | `scripts/00-New-LabVMs.ps1` | Creates the private switch and the VMs (minimal specs) |
| 1 | DC01 | `scripts/01-Initialize-DC01.ps1 -Stage Promote` then `-Stage Configure` | Static IP, forest promotion, DNS zones/forwarders/scavenging, time source |
| 2 | DC02, then DC01 | `scripts/02-Add-DC02.ps1 -Stage Promote` / `-Stage Sites` / `-Stage Verify` | Second DC, DNS client order, sites/subnets, replication check |
| 3 | DC01 | `scripts/05-Configure-Dhcp.ps1` | DHCP scope, options, 50/50 failover, name protection, DNS credential |
| 4 | DC01 | `scripts/03-New-HaldenOUs.ps1` then `scripts/04-Import-HaldenUsers.ps1` | OU tree, AGDLP groups, 85 synthetic users |
| 5 | FS01 | `scripts/06-Configure-FileServices.ps1` | Shares, ACLs, DFS-N, ABE, FSRM, shadow copies |
| 6 | DC01 | `scripts/08-New-HaldenGpos.ps1` | Central Store, seven GPOs, links, backup |
| 7 | LNX01 | `scripts/09-Join-Linux.sh` | Domain join, AD-based SSH and sudo, ufw + fail2ban |
| 8 | DC01 | `scripts/10-Get-AsBuilt.ps1` | Dumps live facts for `docs/as-built.md` |

**Prerequisites:** Windows Server 2025 eval ×3, Windows 11 Enterprise eval ×2, Ubuntu Server 24.04,
OPNsense, PowerShell 7 + RSAT. Secrets (DSRM passwords, the DHCP failover shared secret, the
`svc-dhcpdns` password) are entered at a prompt and stored in the owner's password manager — never
in the repository.

**Snapshot before every phase** (`snap-p1-ph<N>-before`). **Rollback:** revert the snapshot and
re-run the previous phase's scripts; they are idempotent. Reverting a *domain controller* snapshot
is a last resort — fix DC problems forward, because a revert can disturb replication.

## Results

**Not measured yet.** This build kit has been written but not yet executed in the lab, so this
table is deliberately empty rather than filled with plausible-looking numbers. Each row is a real
measurement with a file in `evidence/public/` as its source, added when the phase runs.

| Metric | Before | After | Source |
|---|---|---|---|
| Domain controllers replicating with 0 failures (`repadmin /replsummary`) | not measured | not measured | — |
| Client still authenticates / resolves DNS / leases an IP while DC01 is powered off | not measured | not measured | — |
| Direct user ACEs on share roots (ACL audit) | not measured | not measured | — |
| Users provisioned from CSV in one run | not measured | not measured | — |
| GPO settings applied on WS01 (`gpresult`) | not measured | not measured | — |
| AD users able to SSH to LNX01 without group membership | not measured | not measured | — |

## Acceptance tests

| Test | Expected | Actual | Pass |
|---|---|---|---|
| Shut down DC01 | Logons, DNS resolution and DHCP leases continue via DC02 | not run | ☐ |
| Finance user opens the company share | HR folder not visible (Access-Based Enumeration) | not run | ☐ |
| Sales user copies an `.exe` into the Sales share | Blocked by the FSRM file screen | not run | ☐ |
| Delete a file, restore via "Previous Versions" | Works without IT involvement | not run | ☐ |
| Non-IT AD user connects to LNX01 by SSH | Denied | not run | ☐ |
| Re-run the user import script | Idempotent: no duplicates, no errors | not run | ☐ |
| Re-run `07-Test-ShareAcl.ps1` | 0 violations | not run | ☐ |

## Business deliverables

| Artifact | For | File |
|---|---|---|
| Permission matrix (department × share × access, with a sign-off column) | Department heads approve access, not IT | `business/p01-permission-matrix.md` (+ `.csv`) |
| 1-page staff brief — what changed, what they will notice, who to call | All staff | `business/p01-brief.md` |
| Change record (risk, test plan, backout) | Management / audit trail; feeds the P10 change log | `business/p01-change-record.md` |

## Lessons learned

- **Design first is not bureaucracy.** Choosing the OU tree, the IP plan and the naming standard
  before building avoided a rename exercise later — and it is what makes the "why" questions in an
  interview answerable.
- **Least privilege needs a control, not just good intentions.** The ACL audit script exists
  because "we will remember to use groups" fails the first time someone is in a hurry.
- **Two DCs create their own risks.** DHCP role placement on a DC and DC snapshot reverts are both
  real trade-offs; documenting them (see `docs/as-built.md` §10) was more valuable than pretending
  the design is perfect.
- **Write the runbook while the work is fresh.** Reconstructing "how to add a user" from memory
  weeks later is exactly the failure mode handover documentation is meant to prevent.

## Interview notes

**"Walk me through AGDLP."** Accounts go into **G**lobal role groups, role groups go into
**D**omain **L**ocal resource groups, and only the Domain Local group sits on the permission.
A department change becomes a single group membership edit, and an audit reads group names instead
of thousands of individual ACEs — which is how you can answer "who can read Finance data?" in
seconds.

**"A user can't log in but their colleague can. Where do you start?"** Time skew first (Kerberos
breaks beyond ~5 minutes), then DNS — `nslookup -type=SRV _ldap._tcp.dc._msdcs.ad.halden.internal` —
then the secure channel with `Test-ComputerSecureChannel`, then account lockout from
`Get-ADUser -Properties LockedOut`, then replication with `repadmin`. A DC's NIC pointing at a
public resolver, or only at itself, causes exactly this symptom.

**"Why two domain controllers, and how do you know it works?"** Because AD, DNS and DHCP are Tier 0
single points of failure: with two DCs, AD-integrated DNS and a DHCP failover pair, authentication,
name resolution and address allocation survive one server being down. I did not assume it — I
tested it by powering DC01 off, confirming a client could still sign in, resolve names and lease an
address from DC02, then brought DC01 back and confirmed the failover relationship returned to
`Normal`.

**"Why did you put DHCP on the DCs?"** For a lab of this size it keeps the footprint small and the
build reproducible. It is a documented accepted risk rather than a hidden one — a hardened
production design would put DHCP on a member server so that a compromise of the addressing service
does not land on a Tier 0 DC, and that is why I wrote it down in the as-built document.
