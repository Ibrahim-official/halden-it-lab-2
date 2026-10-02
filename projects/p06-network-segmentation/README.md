# P6: Network Segmentation, Secure Remote Access VPN and Enterprise Wi-Fi

> Home-lab project in an isolated, simulated 85-user company ("Halden Distribution Ltd.").
> Presented as a home lab on the portfolio site — never as employment experience.
> The lab never exposes a service to the internet, and the network WAN side is described only as
> **Hyper-V Default Switch (NAT)** — no wide-area address is recorded anywhere in this project.

**Status:** build kit complete — **lab execution pending** · **Build order:** 8 of 10 · **Depends on:** P1, P3
**Plan:** [`docs/plan/P06-network-segmentation-vpn-wifi.md`](../../docs/plan/P06-network-segmentation-vpn-wifi.md) · **Design:** [`docs/00-design.md`](./docs/00-design.md) · **Rule matrix:** [`configs/p06-zone-rule-matrix.md`](./configs/p06-zone-rule-matrix.md) · **Site page source:** [`showcase.md`](./showcase.md) · **Progress:** [`PROGRESS.md`](../../PROGRESS.md)

## Problem

Halden's network is flat: guest Wi-Fi, the CCTV recorder, printers, warehouse scanners, laptops and
servers all share one subnet. Anything that reaches the network can reach everything on it — so one
infected laptop can talk directly to the domain controllers, the file server and the backup server.
The Wi-Fi password has been unchanged for three years and is written on the break-room wall, so every
visitor who has ever asked for it still knows it. Remote staff reach the file server through a remote
desktop port exposed to the internet, which is one of the most common ways ransomware gets in;
exploitation of edge devices and VPNs was a leading growth vector in the Verizon DBIR 2025. A network
in that state does not have a security boundary at all — it has a shared password and a hope.

## What I built

- **Six firewall-enforced zones** on OPNsense FW01 (SERVERS, WAREHOUSE, USERS-HQ, MGMT, GUEST, IOT)
  plus a VPN pool, replacing one flat subnet, with **deny by default** between all of them.
- **A 24-rule matrix where every exception has a number, an owner and a justification**, applied in a
  documented order because OPNsense evaluates rules top-down with first match wins. Aliases (`DCs`,
  `AD_PORTS`, `RFC1918`) keep the rules readable and a subnet change to one edit.
- **Egress and DNS control**: clients resolve names only through the domain controllers, outbound DNS
  to anyone else is blocked and logged, and outbound SMB and remote desktop are blocked outright.
- **Exposed remote desktop removed**, replaced by an **OpenVPN road-warrior** server with a unique
  certificate per device, authenticated through **NPS/RADIUS against an AD group** and protected by a
  **second factor** (Entra MFA through the NPS extension, or OPNsense TOTP as the lab fallback).
- **Least-privilege remote access**: a VPN user gets the same access as being in the office and is
  explicitly denied the management zone, where the PAW, the hypervisor and the backup repository live.
- **A WireGuard site-to-site tunnel** joining FW02 (warehouse) to HQ, carrying DHCP relay traffic,
  AD authentication and file access for site 2 across one restricted peer relationship.
- **Certificate-based 802.1X Wi-Fi (EAP-TLS)** on an internal AD CS PKI: device certificates issued to
  a purpose-built template and autoenrolled by Group Policy, replacing a shared pre-shared key so
  there is no password on the air for an evil-twin access point to harvest.
- **An isolated guest network** on its own VLAN with client isolation, a voucher process at reception
  and a written acceptable-use notice.
- **An automated segmentation test suite** — 47 defined connections across the six zones, run from a
  host in each zone, written to a results CSV in the `N/N PASS` shape, plus a separate guest and IoT
  isolation test. Configuration is not proof; the test is.
- **Documentation as a deliverable**: design document, as-built document with an empty Verified column,
  four runbooks, an L3 architecture diagram (`.drawio` + `.svg`), an IP plan, and a business layer
  (executive brief, access policy, business-facing zone matrix, guest notice, change record, staff
  VPN guide).

## Architecture

![P6 zone architecture](docs/diagrams/p06-architecture.svg)

Six VLAN zones hang off a single 802.1Q trunk on FW01, and every flow between them is a documented
exception to a default deny. The three flows worth naming: a staff workstation reaches the domain
controllers on a specific port list (miss the RPC range and Group Policy breaks in a way that looks
like a DNS fault); a remote user reaches the same services over the VPN but nothing in the management
zone; and a guest reaches the internet and nothing else at all. FW02 carries the warehouse across a
WireGuard tunnel with one restricted peer relationship rather than a copy of the HQ rule set.

## How to reproduce

Run in order. Every script is lab-guarded (it refuses to run outside `ad.halden.internal` / a host
carrying `/etc/halden-lab`), idempotent, and previews by default. **Mode A applies:** the owner runs
each script against the lab; the firewall scripts are never pointed at anything outside the lab.

| Order | Where | Script | Does |
|---|---|---|---|
| 0 | any lab host | `scripts/00-Test-P6Preflight.sh` | Read-only: validates the config files, prints the zone/VLAN/rule plan, greps for secrets |
| 1 | owner → FW01 | `scripts/01-Apply-OpnSenseNetworks.sh` | VLANs, interface assignments, DHCP relay, aliases, then the ordered rule set (dry-run default) |
| 2 | DC01 | `scripts/02-Set-WindowsDhcpScopes.ps1` | USERS-HQ and WAREHOUSE scopes added to the `HQ-Failover` pair |
| 3 | DC01 | `scripts/03-Set-AdSitesSubnets.ps1` | AD Sites and Services subnets so clients pick a local DC |
| 4 | FS01 | `scripts/04-New-NpsRadiusPolicy.ps1` | NPS role, VPN/Wi-Fi groups, network policies; prints the steps that touch secrets |
| 5 | owner → FW01 | `scripts/05-Configure-OpenVpnServer.sh` | Removes the RDP forward; configures the VPN with RADIUS and a second factor |
| 6 | owner → FW01/FW02 | `scripts/06-Configure-WireGuardS2S.sh` | Site-to-site tunnel, routing and the rules around it |
| 7 | CA01 | `scripts/07-Install-EnterpriseCa.ps1` | Enterprise Root CA, certificate templates, autoenrollment GPO |
| 8 | DC01 | `scripts/08-Configure-8021xWifi.ps1` | Wireless GPO and WLAN policy XML; PSK retirement steps |
| 9 | a host in each zone | `scripts/09-Test-Segmentation.sh` | Runs the test plan and writes the `N/N PASS` results CSV |
| 10 | LNX01 | `scripts/10-Test-EapTls.sh` | Validates the RADIUS/EAP-TLS path with `eapol_test` — works without an access point |
| 11 | GUEST and IOT hosts | `scripts/11-Test-GuestIotIsolation.sh` | Guest and IoT isolation, including the one allowed IoT exception |
| 12 | owner → FW01/FW02 | `scripts/12-Export-ConfigBackup.sh` | Config export (git-ignored raw) plus a sanitised summary for Git |
| — | anywhere | `scripts/report/segmentation_report.py` | Turns the results CSVs into a report and a verification matrix |

**Prerequisites.**

- **Owner approval before anything network-related (AGENTS.md R6).** This project changes the network
  itself. Nothing runs without the owner's explicit go-ahead, and every change targets FW01/FW02 or
  the lab hypervisor switch only. The home router and the home LAN are never touched (R1).
- **A VLAN-aware bridge on the lab host.** Hyper-V: `Set-VMNetworkAdapterVlan` per VM NIC. Proxmox: a
  VLAN-aware `vmbr1` with per-VM tags. Without it there are no VLANs to enforce.
- **FW02** (a second small OPNsense VM, VLAN 20, `192.168.20.1`) and **CA01** (the internal enterprise
  CA, VLAN 10, `192.168.10.43`) created in this project.
- **FS01** carries the NPS/RADIUS role; **DC01/DC02** need the two new DHCP scopes and the AD subnets.
- **Windows Server 2025 / Windows 11 Enterprise evaluation ISOs**, OPNsense, `nmap`, `eapol_test`
  (from `wpa_supplicant`), `jq` for the firewall scripts.
- **Secrets live in the owner's password manager only:** the OPNsense API key and secret, the RADIUS
  shared secret, WireGuard and OpenVPN private keys, and the certificate private keys. They are
  generated on the device, are never committed, and the firewall export that contains them is never
  published. See [`configs/p06-certificate-plan.md`](./configs/p06-certificate-plan.md).
- **An access point is optional.** Without one, `eapol_test` still validates the RADIUS and
  certificate path — but the write-up says which of the two was actually done.

**Snapshot before every phase** (`snap-p6-ph<N>-before` on each VM the phase touches). **Rollback:** the
primary backout for any firewall change is the configuration export from script 12 — restoring it
returns the entire rule set in minutes. Beyond that, revert the snapshot and re-run the previous
phase's scripts, which are idempotent. Keep console access to FW01 open during every change, and never
re-apply the remote desktop port forward as a "rollback": that forward is the problem this project
removes. Reverting a *domain controller* snapshot is a last resort — fix DC problems forward.

## Results

**Not measured yet.** This build kit has been written but not yet executed in the lab, so this table
is deliberately empty rather than filled with plausible-looking numbers. Each row is a real
measurement with a file in `evidence/public/` as its source, added when the phase runs.

| Metric | Before | After | Source |
|---|---|---|---|
| Segmentation test outcomes (`N/N PASS`, hosts in every zone) | not measured | not measured | — |
| Guest and IoT isolation outcomes | not measured | not measured | — |
| Remote desktop reachable from the lab WAN (filtered vs open) | not measured | not measured | — |
| VPN logons denied for a non-member (NPS event 6273) | not measured | not measured | — |
| VPN logons granted with a second factor (NPS event 6272) | not measured | not measured | — |
| Management zone reachable over the VPN | not measured | not measured | — |
| `eapol_test` result against NPS (EAP-TLS) | not measured | not measured | — |
| Switches, printers, servers, laptops on one subnet | not measured | not measured | — |
| Inbound port forwards on the firewall | not measured | not measured | — |
| Firewall rules without a documented owner and justification | not measured | not measured | — |

## Acceptance tests

| Test | Expected | Actual | Pass |
|---|---|---|---|
| Run the segmentation suite from a host in each zone | Every expected-open path open, every expected-blocked path blocked (100% of the 47 defined connections as the matrix says) | not run | ☐ |
| Guest device attempts to reach any `192.168.x` internal address (DC DNS/SMB, FS01 SMB, LNX01 SSH, OPS01 HTTPS, MGMT RDP, FW01 UI) | All blocked or unreachable; internet still works | not run | ☐ |
| IoT device attempts to reach anything but its one allowed share | FS01 SMB allowed; DC SMB/LDAP, LNX01 SSH, OPS01 HTTPS, MGMT RDP blocked | not run | ☐ |
| Scan the lab WAN for the remote-desktop port | Filtered, not open (the forward has been removed) | not run | ☐ |
| A user not in `G_VPN_Users` attempts a VPN login | Rejected; NPS event 6273 with a reason code | not run | ☐ |
| A user in `G_VPN_Users` logs in | Second factor prompted, then a tunnel; FS01 reachable, MGMT RDP unreachable | not run | ☐ |
| A domain computer connects to `Halden-Corp` | EAP-TLS succeeds (certificate issued by the Halden CA) | not run | ☐ |
| A device without a certificate connects to `Halden-Corp` | Rejected | not run | ☐ |
| A warehouse client (VLAN 20) after the tunnel is up | DHCP via relay, AD authentication, a mapped drive, `nltest /dsgetsite` returns `WAREHOUSE` | not run | ☐ |
| A client tries an external DNS resolver | Times out or is redirected; resolution through the DCs still works | not run | ☐ |
| Re-run `01-Apply-OpnSenseNetworks.sh` after a successful apply | Idempotent: no duplicate rules, no errors | not run | ☐ |
| Re-run `02-Set-WindowsDhcpScopes.ps1` | Idempotent: scopes skipped, failover membership unchanged | not run | ☐ |

## Business deliverables

| Artifact | For | File |
|---|---|---|
| Executive brief (1 page): why segmentation matters — one compromised laptop versus the whole company | Managing Director, department heads | `business/p06-exec-brief.md` |
| Network access policy: who may reach what, remote-access rules, guest terms, exception process | Management, for approval | `business/p06-network-access-policy.md` |
| Zone and service matrix in business language, with no ports to decode | Managers | `business/p06-zone-service-matrix-business.md` |
| Guest Wi-Fi acceptable-use notice | Visitors and reception | `business/p06-guest-wifi-notice.md` |
| Change record: risk, phase plan, test plan, comms and backout for a high-risk change | Management / audit trail; feeds the P10 change log | `business/p06-change-record.md` |
| Working-from-home VPN guide (1 page, setup and troubleshooting) | All staff with remote access | `business/p06-remote-access-user-guide.md` |

## Lessons learned

- **A rule matrix is a design tool, not paperwork.** Writing the matrix before touching the firewall
  forced the awkward questions early: which zone needs which port, who owns the exception, and what
  happens when someone forgets one. Doing it after the fact would have produced a description of
  whatever got configured rather than a decision about what should be.
- **The order of operations is a safety control.** VLANs, then interfaces, then the anti-lockout path,
  then aliases, then rules. Writing rules first is how people lock themselves out of their own
  firewall — and a firewall you cannot reach is an outage, not a change.
- **"Configured" is not "verified".** The test suite exists because a rule list tells you what you
  intended. A blocked path in a results CSV tells you what actually happens, and the difference
  between those two things is the entire value of the project.
- **Group Policy is the sneaky failure mode.** The AD port list including the RPC dynamic range is the
  one detail that decides whether a rule change is a success or a support queue, and it is invisible
  until someone cannot process policy.
- **Secrets decided the file layout.** Deciding up front that private keys are generated on the device
  and that the firewall export is never published removed a whole category of later mistakes.

## Interview notes

**"How do you know segmentation actually works, rather than assuming it?"** By attempting every path
myself and recording what happens. The suite defines 47 connections across the zones — the AD and file
ports a user needs, and the paths a guest, an IoT device or a remote user must not have — and runs
them from a host inside each zone, not from the firewall. A `blocked` expectation only passes when the
port is closed, filtered or unreachable, and an `open` expectation only passes when it is genuinely
open. The results are a CSV, not a paragraph, and I recompute the verdict in my own report tooling so
a hand-edited PASS cannot survive. If a path fails, the firewall's deny log tells me which rule
matched, and the matrix tells me who owns it.

**"Why deny by default with documented exceptions, rather than a long allow list?"** A long allow list
is a snapshot of what someone permitted; a default deny is a policy that fails closed. With deny by
default, forgetting to add a rule breaks something visibly, whereas with a permissive model, forgetting
to remove a rule leaves a hole nobody notices. The written exception also gives the "why is this
allowed?" question an answer with a person's name and a review date on it — which is what makes the
rule base survive staff changes. Every rule in my matrix carries its number in the firewall
description, so a log line points straight back to a justification.

**"A manager asks for a quick exception — what do you say?"** Yes, through the front door. Give me the
source, the destination, the service and the business reason and I will grant the narrowest rule that
does the job — one host and one port where I can, not a whole subnet, and time-boxed if the need is
temporary. What I will not do is add an "allow any" rule, because that is how a rule base rots: the
temporary rule that nobody removes, three years later, is usually the path an attacker uses. The
exception gets a number in the matrix, an owner in the business, and a place in the quarterly review.

**"Why EAP-TLS for Wi-Fi instead of PEAP-MSCHAPv2?"** With PEAP-MSCHAPv2 the user's password travels
inside the tunnel, which means an evil-twin access point plus a careless client (one that skips server
certificate validation) can harvest credentials to reuse elsewhere. EAP-TLS puts a certificate on the
device instead: there is no password to capture and nothing to crack offline, and I can revoke one
device without touching anyone else. The cost is the PKI — an enterprise CA, a template and
autoenrollment — which is real work, and it is why I validated the RADIUS and certificate path with
`eapol_test` before claiming the Wi-Fi works. It also let me retire a shared password that was written
on a wall.
