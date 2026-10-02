# P1: Core Infrastructure Build (AD DS, DNS, DHCP, File Services, GPO, Linux Integration)

> **Pitch:** Built a redundant Windows Server 2025 Active Directory environment for an 85-user company: two domain controllers, DHCP failover, AGDLP-based file-share permissions, a tiered GPO baseline, and AD-joined Linux servers, all scripted in PowerShell and documented as-built.

**Anchor score:** 86 · **Time:** about 2 weeks part-time · **Depends on:** nothing (this is the foundation)

---

## 1. Business problem

Halden has a single aging server acting as DC, file server and print server. There's no redundancy, everyone has "Full Control" on the shared drive, and nobody can say who has access to Finance data. If that server dies, nobody can log in, get an IP address or open a file.

**Why it matters:** AD, DNS and DHCP are Tier 0 dependencies. When they fail, everything fails. Messy share permissions are the main reason ransomware can encrypt a whole company from one infected laptop.

## 2. JD coverage

| Ad | Bullet proven |
|---|---|
| SysAdmin | Administer Windows/Linux servers, Active Directory, DNS, DHCP, file services, core IT systems |
| SysAdmin | Permissions and groups based on least privilege (AGDLP) |
| SysAdmin | Accurate configurations, diagrams, technical documentation |
| Officer | Understand company operations and structure (OU design mirrors the org chart) |

## 3. Success criteria (measurable)

- [ ] 2 DCs replicating with no errors (`repadmin /replsummary` shows 0 fails; `dcdiag /e /q` is clean)
- [ ] DHCP failover (load-balance 50/50) survives DC01 being powered off, and clients still lease
- [ ] DNS: AD-integrated zones, reverse zones, scavenging on, conditional forwarders documented
- [ ] 100% of file-share access granted through Domain Local groups (zero direct user ACEs, verified by script)
- [ ] GPO baseline applied and verified with `gpresult /h` on the clients
- [ ] Linux server joined to AD, with SSH login and sudo controlled by AD groups
- [ ] Whole build reproducible from scripts in the repo (`/scripts/01..NN`)

## 4. Architecture

```
                        [ FW01 OPNsense ]  192.168.10.1  (LAN only in P1; VLANs come in P6)
                               |
     ------------------------------------------------------------------
     |            |             |            |           |            |
   DC01         DC02          FS01         LNX01        WS01         WS02
 .10 (PDC,    .11 (GC,      .20 file     .30 Ubuntu   DHCP         DHCP
 GC, DNS,     DNS, DHCP     server,      24.04,       Win 11       Win 11
 DHCP pri)    partner)      DFS-N,       realmd/SSSD
                            FSRM, VSS
Domain: ad.halden.internal   NetBIOS: HALDEN   Functional level: Windows Server 2025
```

### OU design (mirrors the business; delegation-ready)

```
ad.halden.internal
├── _Admin                (Tier 0/1/2 admin accounts & groups; P3 hardens this)
├── Halden
│   ├── Users
│   │   ├── Management ├── Finance ├── HR ├── Sales ├── Operations ├── IT
│   ├── Computers
│   │   ├── Workstations ├── Laptops ├── Kiosks
│   ├── Groups
│   │   ├── Role (G_)      ← Global groups = people by role
│   │   ├── Resource (DL_) ← Domain Local = permission on a resource
│   ├── Servers
│   │   ├── File ├── App ├── Linux
│   └── ServiceAccounts   (gMSA where possible)
└── Disabled             (leavers land here in P2)
```

### Naming standards (document them; interviewers ask)

| Object | Convention | Example |
|---|---|---|
| User | first.last | `sara.khan` |
| Admin account | `adm-t{tier}-first.last` | `adm-t1-sara.khan` |
| Role group (Global) | `G_{Dept}_{Role}` | `G_Finance_Staff` |
| Resource group (DL) | `DL_{Resource}_{Access}` | `DL_Share-Finance_RW` |
| Computer | `{Site}-{Type}-{Num}` | `HQ-WS-001` |
| GPO | `{Scope} - {Purpose} - v{n}` | `WKS - Security Baseline - v1` |

## 5. Tools and cost

Windows Server 2025 eval (x3), Windows 11 Enterprise eval (x2), Ubuntu 24.04, OPNsense, PowerShell 7 + RSAT, draw.io. **Cost: free.**

## 6. Step-by-step action plan

### Phase 0: Plan and document first (half a day)
1. Write `docs/00-design.md`: IP plan, naming standards, OU tree, site layout, DNS design. **Design before you build**, and say so in interviews.
2. Create the IP plan:

   | Range | Use |
   |---|---|
   | .1 | Gateway (FW01) |
   | .10–.19 | Domain controllers |
   | .20–.49 | Servers (static) |
   | .50–.99 | Reserved (printers, infra) |
   | .100–.200 | DHCP scope (clients) |

### Phase 1: First domain controller (Day 1–2)
```powershell
# DC01 — rename, static IP, then promote
Rename-Computer -NewName DC01 -Restart
New-NetIPAddress -InterfaceAlias Ethernet -IPAddress 192.168.10.10 -PrefixLength 24 -DefaultGateway 192.168.10.1
Set-DnsClientServerAddress -InterfaceAlias Ethernet -ServerAddresses 127.0.0.1
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools
Install-ADDSForest -DomainName "ad.halden.internal" -DomainNetbiosName "HALDEN" `
  -ForestMode "Win2025" -DomainMode "Win2025" -InstallDns -SafeModeAdministratorPassword (Read-Host -AsSecureString "DSRM")
```
- Post-promotion: set the DNS client to point at DC02 first and itself second (after DC02 exists). This avoids an island DNS problem.
- Configure **forwarders** (e.g. Quad9 `9.9.9.9`, Cloudflare `1.1.1.1`), create the **reverse lookup zone** `10.168.192.in-addr.arpa`, and enable **scavenging** (7-day no-refresh/refresh).
- Configure the **PDC emulator as the authoritative time source**:
  `w32tm /config /manualpeerlist:"time.windows.com,0x8" /syncfromflags:manual /reliable:yes /update`

### Phase 2: Second DC + replication health (Day 2–3)
```powershell
Install-WindowsFeature AD-Domain-Services, DNS -IncludeManagementTools
Install-ADDSDomainController -DomainName "ad.halden.internal" -InstallDns -Credential (Get-Credential) `
  -SafeModeAdministratorPassword (Read-Host -AsSecureString)
# Verify
repadmin /replsummary
repadmin /showrepl
dcdiag /e /q
Get-ADDomainController -Filter * | Select Name, IsGlobalCatalog, OperationMasterRoles
```
- Rename `Default-First-Site-Name` to `HQ` and create a subnet object `192.168.10.0/24`. Add a second site `WAREHOUSE` (192.168.20.0/24) now so P6 has somewhere to attach to.
- **Evidence:** screenshot the clean `repadmin /replsummary` output.

### Phase 3: DHCP with failover (Day 3)
```powershell
Install-WindowsFeature DHCP -IncludeManagementTools    # on DC01 and DC02
Add-DhcpServerInDC -DnsName dc01.ad.halden.internal -IPAddress 192.168.10.10
Add-DhcpServerv4Scope -Name "HQ-Clients" -StartRange 192.168.10.100 -EndRange 192.168.10.200 -SubnetMask 255.255.255.0 -LeaseDuration 8.00:00:00
Set-DhcpServerv4OptionValue -ScopeId 192.168.10.0 -Router 192.168.10.1 -DnsServer 192.168.10.10,192.168.10.11 -DnsDomain ad.halden.internal
Add-DhcpServerv4Failover -Name "HQ-Failover" -PartnerServer dc02.ad.halden.internal -ScopeId 192.168.10.0 `
  -LoadBalancePercent 50 -SharedSecret (Read-Host) -AutoStateTransition $true -MaxClientLeadTime 01:00:00
```
- Enable **DHCP name protection** and configure DHCP to **dynamically update DNS** using a dedicated low-privilege credential (not a DC computer account). This prevents stale or hijacked DNS records.
- **Test:** power off DC01 → run `ipconfig /release && ipconfig /renew` on WS01 → it gets a lease from DC02. Screenshot it.

### Phase 4: Users, groups, OUs from code (Day 4–5)
1. Create `data/halden-staff.csv` with about 85 fictional users: `First,Last,Department,Title,Manager,Office,EmployeeID,StartDate`.
2. Write `scripts/03-New-HaldenOUs.ps1` and `scripts/04-Import-HaldenUsers.ps1`:
   - Idempotent: check whether the object exists before creating it (`Get-ADUser -Filter` before `New-ADUser`).
   - Set `Department`, `Title`, `Manager`, `EmployeeID`, and `ProtectedFromAccidentalDeletion` on OUs.
   - Generate random initial passwords, force change at next logon, and write credentials **only** to a local file that's excluded by `.gitignore`.
   - Log every action to `logs/import-YYYYMMDD.csv`. This is your audit trail.
3. **AGDLP model:** Accounts → **G**lobal (role) → **D**omain **L**ocal (resource permission) → **P**ermission on the NTFS ACL.
   - `G_Finance_Staff` member of `DL_Share-Finance_RW`
   - `G_Management` member of `DL_Share-Finance_RO`
   - Only DL groups appear on ACLs. **This is the least-privilege story for the interview.**

### Phase 5: File services done properly (Day 6–7)
1. FS01: install `FS-FileServer`, `FS-DFS-Namespace`, `FS-Resource-Manager`.
2. Create shares: `Finance`, `HR`, `Sales`, `Operations`, `Company` (read-all), `Users$` (home drives).
3. **Permission design:**
   - Share permissions: `Authenticated Users: Change` (keep simple; NTFS does the real control)
   - NTFS: remove `Users`/`Everyone`, disable inheritance at the department root, grant DL groups only, `CREATOR OWNER` on home folders
   - Enable **Access-Based Enumeration** (users only see folders they can open)
4. **DFS Namespace:** `\\ad.halden.internal\Company\Finance`, etc. This lets you move servers later without remapping drives. Mention it as a change-management benefit.
5. **FSRM:** quota templates on home drives (e.g. 10 GB soft), a file screen blocking executables in shared folders, and a storage report schedule.
6. **Volume Shadow Copies:** twice daily (7:00, 12:00) for self-service file restores. P8 adds real backups.
7. **Verification script** `scripts/07-Test-ShareAcl.ps1`: walks all share roots and flags any ACE that isn't a `DL_` group, SYSTEM or Administrators. Target: **0 violations**. Commit the report.

### Phase 6: Group Policy baseline (Day 8–9)
Create and link (document each in `docs/gpo/`):

| GPO | Linked to | Key settings |
|---|---|---|
| `DOMAIN - Password & Lockout - v1` | Domain root | 14+ char minimum, lockout 10 attempts / 15 min (P3 adds FGPP) |
| `WKS - Drive Maps - v1` | Workstations OU | GPP drive maps with **item-level targeting** by group (F: = Finance only) |
| `WKS - Security Baseline - v1` | Workstations OU | Placeholder; P4 imports the Microsoft/CIS baseline |
| `WKS - Windows Update - v1` | Workstations OU | Placeholder; P5 configures WSUS rings |
| `USR - Desktop Standards - v1` | Users OU | Screen lock after 10 min, wallpaper/legal notice, block Control Panel for Kiosks |
| `SRV - Remote Management - v1` | Servers OU | WinRM on, firewall rules for mgmt subnet only |

- Create the **Central Store** for ADMX: `\\ad.halden.internal\SYSVOL\ad.halden.internal\Policies\PolicyDefinitions`
- **Verify:** `gpupdate /force`, `gpresult /h C:\gp.html` on WS01. Use RSoP/Group Policy Modeling for a Finance user.
- **Back up** all GPOs: `Backup-GPO -All -Path .\configs\gpo-backup`. Commit to Git (P9 uses this for config-as-code).

### Phase 7: Linux joined to AD (Day 10)
```bash
sudo apt install -y realmd sssd sssd-tools adcli krb5-user packagekit samba-common-bin oddjob oddjob-mkhomedir
sudo realm discover ad.halden.internal
sudo realm join -U administrator ad.halden.internal --computer-ou="OU=Linux,OU=Servers,OU=Halden,DC=ad,DC=halden,DC=internal"
sudo realm deny --all && sudo realm permit -g G_IT_LinuxAdmins
sudo pam-auth-update --enable mkhomedir
echo '%G_IT_LinuxAdmins@ad.halden.internal ALL=(ALL) ALL' | sudo tee /etc/sudoers.d/ad-admins && sudo chmod 440 /etc/sudoers.d/ad-admins
```
- SSH hardening in `/etc/ssh/sshd_config.d/10-halden.conf`: `PermitRootLogin no`, `PasswordAuthentication no` (use keys; AD password only on console), `AllowGroups g_it_linuxadmins@ad.halden.internal`, `MaxAuthTries 3`. Add `fail2ban` and `ufw` allowing 22 from the mgmt subnet only.
- **Test:** an AD user not in the group is denied, and an AD user in the group gets sudo. Screenshot both.

### Phase 8: Document as-built + diagram (Day 11–12)
- `docs/as-built.md`: every server, role, IP, OS build, FSMO holder, DNS config, DHCP scopes, GPO list, share/permission matrix.
- `docs/diagrams/p1-logical.drawio` + PNG export.
- **Runbooks** (short, numbered steps): "Add a new user", "Grant access to a share", "DC is down: what now", "DHCP failover check".

## 7. Business layer (IT Support Officer)

| Artifact | Content |
|---|---|
| `business/p1-permission-matrix.xlsx` | Department × Share × Access (RW/RO/None) with owner sign-off column. **Department heads approve access, not IT.** |
| `business/p1-brief.md` (1 page) | "What changed, why, what users will notice (new drive letters), who to call." |
| `business/p1-change-record.md` | Retroactive change request (feeds the P10 change log). |

## 8. Evidence to capture

`repadmin /replsummary` clean · DHCP failover state "Normal" + renew during DC01 outage · ADUC OU tree · share ACL with DL groups only + script output "0 violations" · `gpresult` HTML · Linux `id user@ad.halden.internal` + denied login · as-built diagram.

## 9. Acceptance tests

| Test | Expected |
|---|---|
| Shut down DC01 | Logons, DNS resolution, DHCP leases all continue via DC02 |
| Finance user opens `\\...\Company\HR` | Folder not visible (ABE) |
| Sales user copies `.exe` into Sales share | Blocked by FSRM file screen |
| Delete a file, restore via "Previous Versions" | Works without IT involvement |
| Non-IT AD user SSHs to LNX01 | Denied |

## 10. Common pitfalls

- A DC pointing to itself only for DNS (island), or to a public DNS server (breaks AD). **Never put 8.8.8.8 in a DC's NIC settings.**
- Using `.local` (mDNS conflicts) or the public company domain (split-brain). `.internal` is correct.
- Granting permissions to users directly "just this once". The script catches it.
- Forgetting time sync. Kerberos fails beyond 5 minutes of skew.
- Snapshotting and reverting DCs carelessly. Win2012+ has VM-GenerationID protection, but document that you know about USN rollback.

## 11. Resume bullets (templates; fill in real numbers)

- Designed and built a redundant **Windows Server 2025 Active Directory** environment (2 DCs, AD-integrated DNS, DHCP failover) for an 85-user simulated organization; validated zero-downtime failover of authentication, DNS and DHCP.
- Implemented **AGDLP least-privilege** file-share permissions across 6 departmental shares with DFS-N, ABE and FSRM; wrote a PowerShell ACL audit that confirmed **0 direct-user permissions**.
- Automated OU, group and user provisioning for **85 accounts** from CSV with idempotent, logged PowerShell scripts; integrated Ubuntu servers into AD via SSSD with group-based SSH and sudo control.

## 12. Interview talking points (STAR)

- **"Walk me through AGDLP."** Explain Accounts → Global → Domain Local → Permission, and why: role changes become one group change, and audits read the groups instead of thousands of ACLs.
- **"A user can't log in, and others can. Where do you start?"** Time sync, DNS (`nslookup -type=SRV _ldap._tcp.dc._msdcs.ad.halden.internal`), secure channel (`Test-ComputerSecureChannel`), account lockout (`Get-ADUser -Properties LockedOut`), replication.
- **"Why two DCs?"** AD, DNS and DHCP are Tier 0 and single points of failure. You tested it by shutting DC01 down.

## 13. AI-ready build prompt

```text
You are a senior Windows/Linux systems administrator mentoring me through a homelab capstone project.
Project: P1 Core Infrastructure Build for a fictional 85-user company "Halden Distribution Ltd".
Environment: Proxmox (or Hyper-V) host with [RAM] GB RAM. VMs: DC01, DC02, FS01 (Windows Server 2025 eval),
WS01/WS02 (Windows 11 Enterprise eval), LNX01 (Ubuntu 24.04), FW01 (OPNsense). Domain: ad.halden.internal.
IP plan: 192.168.10.0/24, gateway .1, DCs .10/.11, FS01 .20, LNX01 .30, DHCP .100-.200.

Goals: 2 replicating DCs, DHCP failover, AD-integrated DNS with reverse zones and scavenging, OU tree mirroring
departments (Management, Finance, HR, Sales, Operations, IT), AGDLP group model, file server with DFS-N, ABE,
FSRM and shadow copies, a GPO baseline, and Ubuntu joined to AD with group-based SSH/sudo.

How to work with me:
1. Go one phase at a time (Phase 0 design → Phase 8 documentation). Don't jump ahead.
2. For each phase give: purpose (1-2 lines), exact PowerShell/bash commands, what output I should see,
   how to verify, and what to screenshot for my portfolio.
3. Write all scripts idempotent, with logging and comments, and no hard-coded passwords.
4. After I paste my output, diagnose problems before moving on.
5. At the end, generate: as-built doc, permission matrix, 1-page user brief, runbooks, README with before/after
   results, and 3 resume bullets using my real numbers.
Start with Phase 0: help me write docs/00-design.md.
```
