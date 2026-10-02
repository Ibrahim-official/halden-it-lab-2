# P1 — Phase 0: Design document (design before you build)

**Project:** P1 Core Infrastructure Build (AD DS, DNS, DHCP, file services, GPO, Linux integration)
**Company:** Halden Distribution Ltd. (fictional, 85 users) · **Domain:** `ad.halden.internal`
**Status:** Phase 0 complete · **Owner:** Muhammad Ibrahim Akmal · **Mode:** A (Advisor)
**Spec:** [`docs/plan/P01-core-infrastructure-build.md`](../../../docs/plan/P01-core-infrastructure-build.md)

> Why design first: AD, DNS and DHCP are Tier 0 — when they fail, everything fails. Getting the
> IP plan, naming standards and OU shape wrong means living with it for the next nine projects.
> Documenting the design now also gives interview answers about *why*, not just *what*.

---

## 1. Goal and scope

Build the foundation the whole portfolio stands on:

- Two replicating domain controllers (Windows Server 2025) with AD-integrated DNS
- DHCP failover
- File services (DFS-N, ABE, FSRM, shadow copies) with AGDLP least-privilege permissions
- A tiered GPO baseline
- One Ubuntu server joined to AD with group-based SSH and sudo
- As-built documentation, runbooks and diagrams

Out of scope for P1: email, cloud identity (P2), security hardening (P3/P4), backups (P8),
VLAN segmentation (P6). The VLAN design exists below but is applied in P6.

## 2. Business context (why this exists)

Halden has one aging server doing DC, file and print work at once. No redundancy, everyone holds
Full Control on the shared drive, and nobody can say who can read Finance data. If that server
dies, nobody can log in, get an IP address or open a file. Messy share permissions are also how
ransomware encrypts an entire company from one infected laptop.

**Success = the measurable criteria** in the P1 plan (2 DCs replicating with zero errors, DHCP
failover surviving DC01 outage, 0 direct user ACLs, Linux joined with AD-based access, the whole
build reproducible from scripts).

## 3. Design principles

1. **Everything as code and scripted** (`/scripts/01..NN`, idempotent, logged) — rebuildable, and
   the scripts are part of the portfolio evidence.
2. **Least privilege by construction (AGDLP):** Accounts → Global groups → Domain Local groups →
   Permission on the resource. Only `DL_` groups ever appear on an ACL.
3. **Name things so they self-document:** consistent conventions (§5) for users, groups,
   computers and GPOs.
4. **Evidence first:** every phase defines what to screenshot/save *before* it runs (§13).
5. **Snapshot before every phase** (§14), every change gets a rollback note.

## 4. Lab host and VM plan

Hypervisor: **Hyper-V on Windows 11 Pro** (decision D9). Minimal specs: dynamic memory, thin VHDX,
Server Core for DC02/FS01. Peak P1 footprint is about 12 GB if every VM runs at its maximum; the
host needs 16 GB. Power off what you are not using. `scripts/00-New-LabVMs.ps1` creates the VMs.

| VM | Role | OS | vCPU | RAM (start-max) | Disk | IP (P1, flat LAN) | Notes |
|---|---|---|---|---|---|---|---|
| HOST01 | Hypervisor | Win 11 Pro + Hyper-V | - | 16 GB host | - | 192.168.10.5 | Checkpoint home |
| FW01 | Gateway (LAN only in P1) | OPNsense | 1 | 0.5-1 GB | 8 GB | 192.168.10.1 | WAN = Hyper-V Default Switch (NAT) |
| DC01 | DC, DNS, DHCP primary, PDC | Server 2025 (Desktop) | 2 | 1-2 GB | 40 GB | 192.168.10.10 | |
| DC02 | DC, DNS, DHCP partner | Server 2025 Core | 2 | 1-2 GB | 40 GB | 192.168.10.11 | |
| FS01 | File server | Server 2025 Core | 2 | 1-2 GB | 60 GB | 192.168.10.20 | |
| LNX01 | AD-joined app server | Ubuntu Server 24.04 | 1 | 0.5-1 GB | 20 GB | 192.168.10.30 | realmd/SSSD |
| WS01 | User workstation | Windows 11 Enterprise eval | 2 | 2-4 GB | 64 GB | DHCP | 4 GB is the Win 11 minimum |
| WS02 | 2nd workstation / PAW | Windows 11 Enterprise eval | 2 | 2-4 GB | 64 GB | DHCP | created in P3, not P1 |

Later projects add: OPS01 (.40) in P9, SIEM01 (.41) in P7, BKP01 (.42) in P8, CA01 (.43) in P6.

## 5. IP plan (192.168.10.0/24 in P1)

| Range | Use |
|---|---|
| .1 | Gateway (FW01) |
| .10–.19 | Domain controllers (static) |
| .20–.49 | Servers (static) |
| .50–.99 | Reserved: printers, infrastructure, DHCP/DNS/DC service accounts |
| .100–.200 | DHCP scope for clients |
| .201–.254 | Reserved for future static use |

**Target VLAN plan (applied in P6, see LAB-INVENTORY.md):** VLAN 10 SERVERS
192.168.10.0/24 (stays) · VLAN 20 WAREHOUSE 192.168.20.0/24 · VLAN 30 USERS-HQ
192.168.30.0/24 · VLAN 40 MGMT 192.168.40.0/24 · VLAN 50 GUEST · VLAN 60 IOT ·
VPN pool 192.168.70.0/24.

## 6. Naming standards

| Object | Convention | Example |
|---|---|---|
| User | `first.last` | `sara.khan` |
| Admin account | `adm-t{tier}-first.last` | `adm-t1-sara.khan` |
| Role group (Global) | `G_{Dept}_{Role}` | `G_Finance_Staff` |
| Resource group (Domain Local) | `DL_{Resource}_{Access}` | `DL_Share-Finance_RW` |
| Computer | `{Site}-{Type}-{Num}` | `HQ-WS-001` |
| Server | short role name | `DC01`, `FS01`, `LNX01` |
| Service account | `svc-{purpose}` or `gmsa-{purpose}` | `svc-dhcpdns`, `gmsa-sql` |
| GPO | `{Scope} - {Purpose} - v{n}` | `WKS - Security Baseline - v1` |
| OU | business name, singular/plural as in tree | `Finance`, `Workstations` |

## 7. OU design (mirrors the org chart; delegation-ready)

```
ad.halden.internal
├── _Admin                     ← Tier 0/1/2 admin accounts & groups (P3 hardens this)
├── Halden
│   ├── Users
│   │   ├── Management ├── Finance ├── HR ├── Sales ├── Operations ├── IT
│   ├── Computers
│   │   ├── Workstations ├── Laptops ├── Kiosks
│   ├── Groups
│   │   ├── Role (G_)          ← Global groups = people by role
│   │   ├── Resource (DL_)     ← Domain Local = permission on a resource
│   ├── Servers
│   │   ├── File ├── App ├── Linux
│   └── ServiceAccounts        ← gMSA where possible
└── Disabled                   ← leavers land here (P2)
```

## 8. AD sites and services

| Site | Subnet | Notes |
|---|---|---|
| HQ (renamed from Default-First-Site-Name) | 192.168.10.0/24 | All P1 hosts |
| WAREHOUSE | 192.168.20.0/24 | Created now so P6 has a site to attach to; used when FW02 exists |
| (P6 adds) | 192.168.30.0/24 → HQ | Users VLAN after segmentation |

The `/24` subnet below the site is not required for P1 function, but creating it now makes the
site topology real and demonstrates that clients pick a local DC.

## 9. DNS design

| Item | Decision |
|---|---|
| Zones | AD-integrated forward zone `ad.halden.internal`; reverse zone `10.168.192.in-addr.arpa` |
| Zone transfers | None (AD-integrated replication only) |
| Scavenging | Enabled: no-refresh 7 days, refresh 7 days |
| Forwarders | Quad9 `9.9.9.9` + Cloudflare `1.1.1.1` (P6 may move to OPNsense Unbound with DoT — decide then and document) |
| Conditional forwarders | None initially; external names resolve via forwarders. Document any later addition |
| DC NIC DNS | DC01: DC02 first, itself second (once DC02 exists); DC02: DC01 first, itself second. **Never a public DNS server on a DC NIC** |
| Dynamic updates | Secure only; DHCP updates records with a dedicated low-privilege account (§11) |
| Records | Server A/PTR records static; client records via DHCP; scavenging protects against stale records |

**Why:** if a DC points at itself only, it can be an isolated island that can't resolve AD records
during startup; a public DNS server on a DC NIC breaks AD entirely. Time sync and DNS are the two
most common causes of "user can't log in".

## 10. Time sync

DC01 (PDC emulator) is the authoritative time source for the domain:
`w32tm /config /manualpeerlist:"time.windows.com,0x8" /syncfromflags:manual /reliable:yes /update`.
All other machines inherit time through the domain hierarchy. Kerberos fails beyond ~5 minutes of
clock skew — this is a Phase 1 verification item, not an afterthought.

## 11. DHCP design

| Item | Decision |
|---|---|
| Server roles | DHCP on DC01 + DC02 (common in small business; documented as accepted risk) |
| Scope | `HQ-Clients` 192.168.10.100–192.168.10.200 / /24, lease 8 days |
| Options | 003 Router `192.168.10.1` · 006 DNS `192.168.10.10, 192.168.10.11` · 015 Domain `ad.halden.internal` |
| Failover | `HQ-Failover`, load balance 50/50, MaxClientLeadTime 1 h, auto state transition on |
| Shared secret | Generated strong; stored in the owner's password manager only, entered via prompt |
| Name protection | Enabled (stops rogue clients registering someone else's name) |
| Dynamic DNS | Enabled, using dedicated `svc-dhcpdns` credentials (not a DC computer account) |
| P6 additions | Scopes for 192.168.20.0/24 (warehouse, via relay) and 192.168.30.0/24 (users), added to the same failover relationship |

## 12. Groups and permission model (AGDLP)

Accounts → **G**lobal role groups → **D**omain **L**ocal resource groups → **P**ermission.

| Example | Members | Has access to |
|---|---|---|
| `G_Finance_Staff` | Finance users | (role group only) |
| `G_Management` | Management users | (role group only) |
| `DL_Share-Finance_RW` | `G_Finance_Staff` | Finance share, Change |
| `DL_Share-Finance_RO` | `G_Management`, `G_Finance_Staff` (read) | Finance share, Read |
| `DL_Share-Users_Home` | users (CREATOR OWNER model) | Home folders root |

**Rule:** ACLs contain only `DL_` groups, `SYSTEM` and `Administrators`. Verified by
`scripts/07-Test-ShareAcl.ps1` — target **0 violations**.

## 13. File services design (FS01)

| Share | Purpose | Access via |
|---|---|---|
| `Finance` | Finance department | `DL_Share-Finance_RW` / `_RO` |
| `HR` | HR (restricted) | `DL_Share-HR_RW` / `DL_Share-HR_RO` (Management) |
| `Sales` | Sales | `DL_Share-Sales_RW` |
| `Operations` | Operations/warehouse | `DL_Share-Operations_RW` |
| `Company` | Company-wide read | `DL_Share-Company_RO` |
| `Users$` | Home folders (hidden) | `CREATOR OWNER` per folder |

- **DFS namespace** `\\ad.halden.internal\Company\...` so shares can move servers without
  remapping drives (change-management talking point).
- **ABE** on: users only see folders they can open.
- **FSRM:** 10 GB soft quota templates on home folders; file screen blocks executables in shared
  folders; scheduled storage reports.
- **Shadow copies:** twice daily (07:00, 12:00) for self-service restores. Real backups arrive in P8.

## 14. GPO baseline

| GPO | Linked to | Key settings |
|---|---|---|
| `DOMAIN - Password & Lockout - v1` | Domain root | 14+ char minimum, lockout 10 attempts / 15 min (P3 adds FGPP) |
| `WKS - Drive Maps - v1` | Workstations OU | GPP drive maps with item-level targeting by group |
| `WKS - Security Baseline - v1` | Workstations OU | Placeholder; P4 imports the Microsoft/CIS baseline |
| `WKS - Windows Update - v1` | Workstations OU | Placeholder; P5 configures WSUS rings |
| `USR - Desktop Standards - v1` | Users OU | Screen lock 10 min, legal notice, blocked Control Panel for kiosks |
| `SRV - Remote Management - v1` | Servers OU | WinRM on, firewall rules for management subnet only |

**Central Store** for ADMX: `\\ad.halden.internal\SYSVOL\ad.halden.internal\Policies\PolicyDefinitions`.
**GPO backups** to `configs/gpo-backup` and committed (P9 turns this into config-as-code).

## 15. Linux integration (LNX01)

- `realmd`/`SSSD` join: `realm join -U administrator ad.halden.internal --computer-ou="OU=Linux,..."`
- Access control: `realm deny --all`, then `realm permit -g G_IT_LinuxAdmins`
- Sudo: `/etc/sudoers.d/ad-admins` → `%G_IT_LinuxAdmins@ad.halden.internal ALL=(ALL) ALL`
- SSH hardening: `PermitRootLogin no`, `PasswordAuthentication no`, `AllowGroups
  g_it_linuxadmins@...`, `MaxAuthTries 3`; `fail2ban` + `ufw` allowing 22 from the management
  subnet only.
- **Test evidence:** a non-member AD user is denied; a member logs in and runs sudo.

## 16. Build phases and evidence plan

| Phase | Deliverable | Evidence to capture |
|---|---|---|
| 0 | This design document | (document itself) |
| 1 | DC01 promoted, DNS, reverse zone, scavenging, forwarders | Promotion result, `dcdiag`/DNS screenshots |
| 2 | DC02 promoted, replication healthy, sites/subnets | `repadmin /replsummary` clean, `dcdiag /e /q` |
| 3 | DHCP failover working | Failover state "Normal"; WS01 renews during DC01 outage |
| 4 | Users/groups/OUs from CSV (85 users, scripted, logged) | Import log, ADUC OU tree, idempotent re-run |
| 5 | DFS shares with AGDLP + ABE + FSRM + VSS | ACL audit "0 violations"; blocked folder not visible; `.exe` blocked by FSRM; Previous Versions restore |
| 6 | GPO baseline deployed + Central Store | `gpresult /h` on WS01; GPO backup committed |
| 7 | LNX01 joined; AD-based SSH/sudo | `id user@ad.halden.internal`, allowed/denied login proof |
| 8 | As-built doc, diagram, runbooks | `docs/as-built.md`, draw.io PNG, 4 runbooks |

## 17. Acceptance tests (run before calling P1 Done)

| Test | Expected |
|---|---|
| Shut down DC01 | Logons, DNS and DHCP continue via DC02 |
| Finance user opens `\\...\Company\HR` | Folder not visible (ABE) |
| Sales user copies `.exe` into Sales share | Blocked by FSRM file screen |
| Delete a file; restore via Previous Versions | Works without IT involvement |
| Non-IT AD user SSHs to LNX01 | Denied |
| Re-run user import script | Idempotent: no duplicates, no errors |

## 18. Snapshot and rollback plan

- **Before every phase:** take a hypervisor snapshot of each VM the phase touches, named
  `snap-p1-ph<N>-before` (e.g. `snap-p1-ph3-before`). Rollback = revert that snapshot and re-run
  prior scripts.
- **DC caution:** Windows Server 2012+ protects against USN rollback via VM-GenerationID, but
  reverting a DC discards replication changes and can confuse replication. Prefer forward fixes
  on DCs; snapshot DC changes but tell me before reverting one.
- Phase 0 changed nothing in the lab, so no snapshot was needed. **Phase 1 does change things.**

## 19. Decisions taken (owner delegated all choices; see DECISIONS.md D9-D12)

1. Hypervisor: Hyper-V. 2. NTP: `time.windows.com`. 3. Switch design: private `Halden-LAN`, FW01 WAN on
Default Switch so the home LAN is never touched. 4. UPS: unknown; use Hyper-V checkpoints and shut VMs down cleanly.

## 20. Risks

| Risk | Mitigation |
|---|---|
| DNS island (DC pointing only at itself) | DC NIC ordering per §9; verified during Phase 2 |
| Clock skew breaking Kerberos | Authoritative PDC time source set in Phase 1, verified |
| Accidental-direct ACLs creeping in | ACL audit script; target 0 violations |
| DC snapshot revert causing replication issues | Documented caution §18; forward fixes preferred |
| 16 GB host running out of RAM in later projects | Server Core where useful; run only needed VMs; P7/P8 sized in their plans |
| Evaluation licence expiry | Tracked in `PROGRESS.md` (180/90-day clocks) |

## 21. Interview notes (phase 0)

**"Walk me through AGDLP."** Accounts go into Global role groups, role groups go into Domain Local
resource groups, and only the Domain Local group sits on the ACL. A department change becomes a
group membership change; audits read group names instead of thousands of ACEs.

**"Why two domain controllers?"** AD, DNS and DHCP are Tier 0 single points of failure. Two DCs
with AD-integrated DNS and a DHCP failover pair mean authentication, name resolution and address
allocation survive one server being down — and I proved it by powering DC01 off.

**"A user can't log in but their colleague can. Where do you start?"** Time skew, DNS
(`nslookup -type=SRV _ldap._tcp.dc._msdcs.ad.halden.internal`), secure channel
(`Test-ComputerSecureChannel`), account lockout, then replication (`repadmin`).

---

*Next step: Phase 1 — DC01 (plan §Phase 1). Snapshot first; advertise the changes before running
anything (Mode A: the owner runs the commands and pastes output back).*
