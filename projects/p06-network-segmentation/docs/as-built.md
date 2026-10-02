# P6 as-built — Halden Distribution Ltd. network segmentation, VPN and Wi-Fi

> **Status: build kit complete, lab execution pending.** This document records the **designed**
> configuration from [`00-design.md`](./00-design.md). Every table has an empty **Verified** column
> that is ticked only after the matching phase has actually been run in the lab and the real output
> has been pasted in. Nothing here is presented as a captured result, and no number is claimed until
> it has been measured (AGENTS.md R2).
>
> **How to finish this document:** run the phase scripts, collect the outputs below, then sanitize
> them per AGENTS.md 4.6 and paste them in, replacing *(designed)* with *(verified)*. Evidence files
> go in `evidence/public/` named like `p06-ph6-segmentation-results-ws01.csv`. The firewall export in
> `evidence/raw/` is **never** published, in any form.

## 1. Environment summary

| Item | Designed value | Verified |
|---|---|---|
| Domain | `ad.halden.internal` | ☐ |
| Firewalls | FW01 (HQ, 192.168.10.1), FW02 (warehouse, 192.168.20.1) — OPNsense | ☐ |
| Lab WAN | Hyper-V Default Switch (NAT) — **no address recorded or published** | ☐ |
| Zones live | VLAN 10, 20, 30, 40, 50, 60 and the VPN pool 192.168.70.0/24 | ☐ |
| Inter-zone policy | Deny by default; 24 documented rules in the matrix | ☐ |
| VLAN-aware bridge | `vmbr1`/switch made VLAN-aware with per-VM tags, or Hyper-V `Set-VMNetworkAdapterVlan` | ☐ |

## 2. Zones, interfaces and addressing *(designed)*

| VLAN | Zone | Subnet | Gateway (FW01) | DHCP | Verified |
|---|---|---|---|---|---|
| 10 | SERVERS | 192.168.10.0/24 | 192.168.10.1 | Static | ☐ |
| 20 | WAREHOUSE | 192.168.20.0/24 | 192.168.20.1 (FW02) | Windows DHCP via relay | ☐ |
| 30 | USERS-HQ | 192.168.30.0/24 | 192.168.30.1 | Windows DHCP via relay | ☐ |
| 40 | MGMT | 192.168.40.0/24 | 192.168.40.1 | Static | ☐ |
| 50 | GUEST | 192.168.50.0/24 | 192.168.50.1 | OPNsense DHCP, client isolation | ☐ |
| 60 | IOT | 192.168.60.0/24 | 192.168.60.1 | OPNsense DHCP | ☐ |
| — | VPN-USERS | 192.168.70.0/24 | 192.168.70.1 (ovpns1) | VPN pool | ☐ |
| — | Site link | 10.99.0.0/30 | .1 (FW01) / .2 (FW02) | — | ☐ |

The full address list is [`../data/p06-zone-ip-allocation.csv`](../data/p06-zone-ip-allocation.csv).

## 3. Firewall configuration *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Rule set | 24 rules in the order in `configs/p06-zone-rule-matrix.csv`; first match wins | ☐ |
| Default deny | Rule 24, deny and log, last in the list | ☐ |
| Management zone | Reachable from MGMT only (rules 1, 22, 23) | ☐ |
| Aliases | `DCs`, `FileServers`, `SERVERS_NET`, `MGMT_NET`, `AD_PORTS`, `RFC1918`, … | ☐ |
| Logging | Enabled on the deny rules; deny events reviewed in Phase 6 | ☐ |
| Inbound port forwards | **None** (the RDP forward to the file server is deleted) | ☐ |
| Anti-lockout | MGMT → FW01 web UI allowed before any rule was written; console kept open | ☐ |

## 4. DHCP and AD integration *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Scopes | `USERS-HQ-Clients` 192.168.30.100–200, `WAREHOUSE-Clients` 192.168.20.100–200, lease 8 days | ☐ |
| Options | 003 `x.x.x.1` · 006 `192.168.10.10, 192.168.10.11` · 015 `ad.halden.internal` | ☐ |
| Failover | Both new scopes added to the existing `HQ-Failover` relationship | ☐ |
| Relay | FW01 relays VLAN 20 and VLAN 30 to the Windows DHCP pair | ☐ |
| AD sites and subnets | `192.168.30.0/24` → HQ, `192.168.20.0/24` → WAREHOUSE | ☐ |
| Warehouse site selection | A warehouse client returns `WAREHOUSE` from `nltest /dsgetsite` | ☐ |

## 5. DNS and egress filtering *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Client DNS | DCs only (`192.168.10.10`, `.11`); all other DNS is denied and logged | ☐ |
| Upstream | DCs → Unbound on OPNsense → DNS-over-TLS to a malware-blocking resolver | ☐ |
| Blocklists | Optional Unbound blocklists, kept upstream of AD | ☐ |
| Blocked egress | DNS 53/853 to non-DCs, SMB 445, RDP 3389 | ☐ |
| Rogue DNS | Client attempts to an external resolver are redirected and logged | ☐ |

## 6. Remote access VPN *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| RDP exposure | Removed; the lab WAN shows the port as filtered rather than open | ☐ |
| Protocol | OpenVPN road-warrior, TLS, unique certificate per client, AES-256-GCM | ☐ |
| Authenticator | FW01 → NPS on FS01 (RADIUS) | ☐ |
| Group condition | `G_VPN_Users` (Access-Accept only for members) | ☐ |
| Second factor | Entra MFA through the NPS extension, or OPNsense TOTP as the fallback | ☐ |
| Tunnel | 192.168.70.0/24, split tunnel, internal routes only | ☐ |
| Parity | A VPN user reaches FS01 and the service desk, and **not** the management zone | ☐ |
| Denied user | A non-member is rejected; NPS event 6273 with a reason code | ☐ |
| Access process | Ticket → manager approval → `G_VPN_Users` → quarterly review (P2) | ☐ |

## 7. Site-to-site WireGuard *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| Peers | FW01 `10.99.0.1/30` ↔ FW02 `10.99.0.2/30`, UDP 51820 | ☐ |
| Allowed IPs | Each side restricted to the remote LAN plus the peer tunnel address | ☐ |
| Rules | WAREHOUSE → DCs/FS01/OPS01 on AD and file ports; deny the rest | ☐ |
| Key handling | Private keys generated on the device; only public keys exchanged | ☐ |
| Site 2 client | DHCP via relay, AD authentication, a mapped drive, `nltest /dsgetsite` = WAREHOUSE | ☐ |

## 8. Wi-Fi, PKI and 802.1X *(designed)*

| Item | Designed value | Verified |
|---|---|---|
| CA | Enterprise Root CA on CA01 (`Halden-Root-CA`) | ☐ |
| Templates | `Halden-WiFi-Computer` (Domain Computers, autoenroll), `Halden-RAS-IAS-Server` (FS01) | ☐ |
| Autoenrollment | GPO `WKS - Cert Autoenrollment - v1`; a client shows the certificate in `certutil -store My` | ☐ |
| Corporate SSID | `Halden-Corp`, WPA3-Enterprise (or WPA2-Enterprise), EAP-TLS | ☐ |
| Server validation | Clients validate the NPS certificate and trust only the Halden CA | ☐ |
| RADIUS path | `eapol_test` from LNX01 returns `SUCCESS` | ☐ |
| Guest SSID | `Halden-Guest`, captive portal/voucher, client isolation, VLAN 50, internet only | ☐ |
| Staff PSK | Retired once every domain device carries a certificate | ☐ |
| Committed key material | Public root CA certificate only — see `configs/p06-certificate-plan.md` | ☐ |

## 9. Segmentation verification *(designed: 47 planned connections, results not yet measured)*

| Zone | Planned connections | Result | Verified |
|---|---|---|---|
| USERS-HQ | 11 | not measured | ☐ |
| WAREHOUSE | 8 | not measured | ☐ |
| MGMT | 4 | not measured | ☐ |
| GUEST | 8 (+8 in the dedicated isolation run) | not measured | ☐ |
| IOT | 9 (+8 in the dedicated isolation run) | not measured | ☐ |
| VPN-USERS | 7 | not measured | ☐ |
| **Total** | **47** | **not measured** | ☐ |

The plan is [`../data/p06-segmentation-test-plan.csv`](../data/p06-segmentation-test-plan.csv); the
results files are written by `scripts/09-Test-Segmentation.sh` and summarised by
`scripts/report/segmentation_report.py`. **This table is filled from the results CSVs, never from
expectation.**

## 10. Known gaps and exceptions

| Item | Note |
|---|---|
| Single Enterprise Root CA on one VM | Production: offline root plus issuing CA, both Tier 0 |
| NPS on FS01 (a member server) | Chosen over NPS-on-a-DC precisely to avoid enlarging the Tier-0 attack surface; production would use dedicated RADIUS hosts |
| Split tunnel | Better bandwidth, but the endpoint's own internet posture is not controlled by the VPN; P4's endpoint baseline is the compensating control |
| No local DC/RODC at the warehouse | If the tunnel is down, site 2 cannot authenticate; accepted for the lab and documented |
| RPC dynamic range left wide | Narrowing NTDS/Netlogon RPC ports needs registry changes with their own rollback; offered as an option, not done silently |
| IoT internet blocked | Vendor update requests are handled through a change request naming the specific host, not a blanket allow |
| 802.1X proven with `eapol_test` unless an AP exists | That validates the RADIUS and certificate path, not a physical access point; the write-up states which was done |
| Wardrobe of lab-only shortcuts | DHCP on the DCs (from P1), and a NAT-only WAN, both inherited and re-stated here |

## 11. Configuration management

| Item | Designed value | Verified |
|---|---|---|
| Firewall export | `scripts/12-Export-ConfigBackup.sh`; raw export in `evidence/raw/` (never published) | ☐ |
| Sanitised summary | `evidence/public/p06-ph6-config-summary-fw01.csv` — counts and section names only | ☐ |
| NPS export | `netsh nps export filename="nps.xml" exportPSK=NO` — shared secrets excluded | ☐ |
| Diagrams | L3 logical (`p06-architecture.svg`) and the L2/VLAN layer plan | ☐ |
| Config-as-code | P9 automates these exports into Git and raises a drift alert for unapproved changes | ☐ |
