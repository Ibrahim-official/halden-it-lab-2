# P6: Network Segmentation, Secure Remote Access VPN and Enterprise Wi-Fi

> **Pitch:** Redesigned a flat office network into six firewall-enforced VLAN zones with a default-deny rule matrix and egress filtering. Deployed an AD-integrated remote-access VPN with MFA, a site-to-site WireGuard tunnel to the warehouse, and certificate-based 802.1X (EAP-TLS) Wi-Fi backed by an internal PKI. Segmentation was proven with an automated nmap test matrix.

**Anchor score:** 87 (merged with #21 VLANs, #23 802.1X, #24 rule review, #25 DNS filtering) · **Time:** about 2 weeks · **Depends on:** P1, P3

---

## 1. Business problem

Halden's network is flat: the guest Wi-Fi, CCTV DVR, printers, warehouse scanners, laptops and servers all share one subnet. The Wi-Fi password was last changed three years ago and is written on the break-room wall. Remote staff use a port-forwarded RDP to the file server.

**Market evidence:** exploitation of **edge devices and VPNs** was a leading growth vector in the Verizon DBIR 2025. Flat networks let ransomware move from one infected device to every server. Exposed RDP is one of the most common ransomware entry points.

## 2. JD coverage

| Ad | Bullet proven |
|---|---|
| SysAdmin | Support **firewall, network, VPN, Wi-Fi** and other infrastructure |
| SysAdmin | Access controls based on least privilege (network-level) |
| SysAdmin | Maintain **network diagrams** and configuration documentation |
| SysAdmin | Security checks; unauthorized access prevention |
| Officer | Process: remote-access request and approval; communicate changes to staff |

## 3. Success criteria

- [ ] 6 VLAN zones live; **inter-VLAN traffic default-deny**, with every allow rule documented in a matrix with owner and justification
- [ ] Automated segmentation test: **100% of expected-deny paths blocked, 100% of expected-allow paths open**
- [ ] **No inbound port forwards** (RDP removed); remote access only via VPN with AD group check + MFA
- [ ] Site-to-site WireGuard between HQ and Warehouse firewalls, with AD replication/logons working across it
- [ ] Wi-Fi: EAP-TLS 802.1X for corporate devices, isolated guest network, no shared PSK for staff
- [ ] Egress controls: DNS only via the DCs/resolver, outbound SMB/RDP to the internet blocked
- [ ] Current L3 diagram, IP plan, firewall rule matrix, and config backups in Git

## 4. Target design

| VLAN | Zone | Subnet | DHCP | Purpose |
|---|---|---|---|---|
| 10 | SERVERS | 192.168.10.0/24 | Static | DCs, FS01, LNX01, OPS01, SIEM01, BKP01 |
| 20 | WAREHOUSE (site 2) | 192.168.20.0/24 | Windows DHCP via relay | Warehouse site behind FW02 |
| 30 | USERS-HQ | 192.168.30.0/24 | Windows DHCP via relay | Staff workstations/laptops (WS01) |
| 40 | MGMT | 192.168.40.0/24 | Static | PAW (WS02), hypervisor, AP/switch management |
| 50 | GUEST | 192.168.50.0/24 | OPNsense DHCP | Internet only, client isolation |
| 60 | IOT | 192.168.60.0/24 | OPNsense DHCP | Printers, CCTV, scanners |
| — | VPN-USERS | 192.168.70.0/24 | VPN pool | Remote staff |

```
            Internet
               │
        [FW01 OPNsense HQ] ══════ WireGuard S2S ══════ [FW02 OPNsense Warehouse]
         │ trunk (802.1Q)                                        │
 ┌──────┬┴──────┬────────┬────────┬────────┐                VLAN 20 users/scanners
 V10    V30     V40      V50      V60     VPN pool
SERVERS USERS   MGMT     GUEST    IOT     (OpenVPN + RADIUS/NPS + MFA)
```

**Lab implementation:** In Proxmox, make `vmbr1` **VLAN-aware** and give each VM NIC a VLAN tag. OPNsense gets a trunk NIC with VLAN sub-interfaces. In Hyper-V, set `Set-VMNetworkAdapterVlan -Access -VlanId`. FW02 is a second small OPNsense VM (1 GB RAM).

## 5. Tools and cost

OPNsense (x2), Windows **NPS** (RADIUS), **AD Certificate Services** (Enterprise CA), WireGuard + OpenVPN (in OPNsense), `nmap`, `eapol_test` (from wpa_supplicant) for RADIUS/802.1X testing, draw.io. **Optional:** a used WPA2/3-Enterprise-capable access point (check the local used market) for a real Wi-Fi test. **Cost: free (plus the AP if you buy one).**

## 6. Step-by-step action plan

### Phase 0: Discovery and design (Day 1–2)
1. **Inventory the "as-is"** with an `nmap -sn 192.168.10.0/24` sweep plus the DHCP lease table. Classify every device into a zone (fill in `docs/p6-device-zoning.xlsx`).
2. Build the **firewall rule matrix** *before* configuring anything (`docs/p6-rule-matrix.xlsx`):

   | # | Source | Destination | Ports/Service | Action | Justification | Owner |
   |---|---|---|---|---|---|---|
   | 1 | USERS-HQ | DCs | DNS 53, Kerberos 88, NTP 123, RPC 135, LDAP 389/636, SMB 445, kpasswd 464, GC 3268/3269, RPC dynamic 49152–65535 | Allow | AD authentication & GPO | IT |
   | 2 | USERS-HQ | FS01 | SMB 445 | Allow | File shares | IT |
   | 3 | USERS-HQ | OPS01 | HTTPS 443 | Allow | Helpdesk/GLPI (P9) | IT |
   | 4 | MGMT | ANY internal | ANY | Allow | Administration (PAW) | IT |
   | 5 | ANY internal (not DCs) | Internet | DNS 53/853 | **Block** | Force DNS via DCs (filtering + logging) | IT |
   | 6 | ANY internal | Internet | SMB 445, RDP 3389 | **Block** | Common exfil/lateral routes | IT |
   | 7 | GUEST | RFC1918 | ANY | **Block** | Guest isolation | IT |
   | 8 | IOT | FS01 print/scan share | SMB 445 | Allow | Scan-to-folder | Ops |
   | 9 | IOT | Internet | ANY | Block (allow vendor update hosts only) | CCTV/printers don't need the internet | Ops |
   | 10 | VPN-USERS | same as USERS-HQ | as #1–#3 | Allow | Remote work parity | IT |
   | … | ANY | ANY | ANY | **Deny + log** | Default deny | — |

   Tighten the RPC dynamic range on DCs if you like (you can fix AD replication/NTDS RPC ports via registry). Document the trade-off.
3. Write the **change plan**: migration order (MGMT first → SERVERS → USERS → IOT → GUEST), a maintenance window, rollback (config backup + snapshot), and a user notification. Create a P10 change record.

### Phase 1: VLANs and inter-VLAN routing on OPNsense (Day 3–4)
1. Interfaces → Other Types → VLAN: create 10/30/40/50/60 on the trunk parent. Assign them, set gateway IPs `.1`, and enable.
2. **Anti-lockout:** before touching rules, make sure MGMT → FW01 web UI is allowed and you have console access to the VM.
3. **DHCP relay** on OPNsense for VLAN 30 (and 20 via FW02) → `192.168.10.10, 192.168.10.11`. On Windows DHCP, create scopes `192.168.30.0/24` and `192.168.20.0/24` with options 003/006/015 and **add them to the existing failover relationship** from P1.
4. Move VMs into their VLANs one zone at a time and verify DHCP, DNS, logon and GPO each time.
5. **Update AD Sites & Services:** add subnet objects `192.168.30.0/24` → HQ and `192.168.20.0/24` → WAREHOUSE. Clients then pick the right DC.
6. Enter the firewall rules exactly as in the matrix, using **aliases** (`DCs`, `FileServers`, `AD_Ports`, `RFC1918`) so the rules stay readable. Put the rule number from the matrix in each rule description. **Enable logging on the default-deny rules.**

### Phase 2: Egress filtering and DNS filtering (Day 5)
1. DCs forward to **Unbound on OPNsense**, which uses DNS-over-TLS to Quad9 (malware-blocking resolver), **or** DCs forward straight to Quad9. Choose one and document why.
2. Optional: OPNsense Unbound **DNS blocklists** (ads/malware). In AD environments, keep AD zones on the DCs and do the filtering upstream.
3. NAT port-forward rule to block and redirect rogue DNS (53) from clients back to the DCs, and log it.
4. **Test:** from WS01, `nslookup example.com 8.8.8.8` → times out. `Resolve-DnsName` via the DCs works. A known test malware domain is blocked (use Quad9's documented test domain).

### Phase 3: Remove RDP exposure; remote-access VPN with MFA (Day 6–8)
1. **Delete the RDP port forward.** Before/after: external `nmap -Pn -p 3389 <WAN IP>` shows open → filtered.
2. **RADIUS/NPS:** install the NPS role on FS01 in the lab (in production, use dedicated servers; note that NPS on a DC is common but increases the Tier 0 attack surface). Register it in AD.
   - RADIUS client: FW01 (shared secret 32+ random chars)
   - Network Policy "VPN-Staff": Condition = Windows Group `G_VPN_Users`, auth = MS-CHAPv2 (inside TLS); optional per-group **Filter-Id** / class attribute so IT gets MGMT access and staff don't
3. **OPNsense OpenVPN (road-warrior) server:** TLS auth + certificate per client, auth backend = the RADIUS server, AES-256-GCM, tunnel network 192.168.70.0/24, split tunnel (only internal routes pushed) **or** full tunnel. Pick one and document the security vs bandwidth trade-off.
4. **MFA:** in the M365 trial window, install the **NPS Extension for Microsoft Entra MFA** so VPN logons trigger an Authenticator push (check current licensing and prerequisites on Microsoft Learn). Lab fallback: OPNsense local users with **TOTP**. Either way, the README must show a second factor.
5. Client export package plus a **1-page staff setup guide**.
6. **Access request process:** ticket → manager approval → added to `G_VPN_Users` via P2 → quarterly review in the P2 access review.
7. **Test:** a user not in the group is rejected (NPS event 6273 with reason code). A user in the group gets an MFA prompt and connects, and can reach FS01 but **not** MGMT.

### Phase 4: Site-to-site WireGuard (HQ ↔ Warehouse) (Day 9)
1. FW01 and FW02: VPN → WireGuard → instances with keypairs, tunnel addresses `10.99.0.1/30` and `10.99.0.2/30`, peers with `AllowedIPs` = the remote LAN(s) + tunnel IP. Allow UDP 51820 on each WAN.
2. Static routes/gateways and **firewall rules on the WireGuard interface**. Default deny still applies: only warehouse users → DCs/FS01/OPS01.
3. **Test:** a warehouse client (VLAN 20) gets DHCP via relay across the tunnel, authenticates against a DC, maps drives, and `nltest /dsgetsite` returns `WAREHOUSE`.
4. Note in interviews: in production you'd put an RODC or a local DC at a remote site that needs to keep working through WAN outages.

### Phase 5: 802.1X Wi-Fi with EAP-TLS (Day 10–12)
1. **AD CS:** install an **Enterprise Root CA** on a dedicated server (in the lab, a small VM `CA01` or FS01; document that in production you'd use an offline root + issuing CA, and that the CA is **Tier 0**).
2. Certificate templates: duplicate **Computer** → `Halden-WiFi-Computer` (Client Authentication, autoenroll for Domain Computers). Duplicate **RAS and IAS Server** → issue to the NPS server.
3. GPO `WKS - Cert Autoenrollment - v1` → autoenroll computers. Verify with `certutil -store My` on WS01.
4. NPS policy "Wi-Fi-Corp": condition = NAS-Port-Type Wireless + group `Domain Computers` (or a `G_WiFi_Devices` group), auth = **Microsoft: Smart Card or other certificate (EAP-TLS)**. Explain why it's stronger than PEAP-MSCHAPv2: no password to phish via an evil-twin AP, and nothing to crack.
5. GPO `WKS - Wireless - v1` → SSID `Halden-Corp`, WPA3-Enterprise (or WPA2-Enterprise if the AP lacks WPA3), EAP-TLS, validate server certificate, trust only the Halden CA.
6. **Test without hardware:** from LNX01, use `eapol_test` with a config using the client cert to act as the "access point" against NPS and show `SUCCESS`. **With an AP:** real connection, and the guest SSID maps to VLAN 50 with client isolation and a captive portal/voucher (OPNsense captive portal).
7. Rotate away from the old PSK. Write the **retirement comms**.

### Phase 6: Validate segmentation, document, back up (Day 13–14)
1. `scripts/Test-Segmentation.sh` runs from a test VM in each zone:
   ```bash
   # expected.csv: src_zone,dst_ip,port,expected(open|closed)
   while IFS=, read src dst port exp; do
     res=$(nmap -Pn -p "$port" "$dst" | awk '/\/tcp/{print $2}')
     [[ "$res" == "$exp" || ( "$exp" == "closed" && "$res" == "filtered" ) ]] && s=PASS || s=FAIL
     echo "$src,$dst,$port,$exp,$res,$s"
   done < expected.csv > results-$(hostname).csv
   ```
   Target: **100% PASS**. Commit the results table. **This is the proof that segmentation works, not just that it's configured.**
2. Review firewall logs for denied traffic you didn't expect. Adjust through a change record, or confirm it's correctly blocked.
3. **Config backups:** OPNsense `System → Configuration → Backups` → export XML (strip or encrypt secrets) to Git (P9 automates this). Export NPS config: `netsh nps export filename="nps.xml" exportPSK=NO`.
4. Final diagrams: **L3 logical** (zones, subnets, firewall) and **L2/physical** (lab host, bridges, VLAN tags), plus the IP plan and rule matrix.

## 7. Business layer (IT Support Officer)

| Artifact | Purpose |
|---|---|
| `business/p6-remote-access-standard.md` | Who can have VPN, approval, MFA, acceptable use, review |
| `business/p6-staff-guides/` | VPN setup (1 page), Wi-Fi change notice, guest Wi-Fi voucher procedure for reception |
| `business/p6-change-plan.md` | Migration plan, window, comms, rollback (feeds the P10 change log) |
| `business/p6-summary.md` | Before/after for management: "RDP no longer exposed; guest can't reach company data; ransomware on one laptop can't reach the backups" |

## 8. Evidence to capture

VLAN interface list · rule matrix + OPNsense rules with matching descriptions · external nmap 3389 open → filtered · NPS event 6272 (granted) / 6273 (denied) · VPN MFA prompt · WireGuard handshake + `nltest /dsgetsite` · `eapol_test` SUCCESS (or a real Wi-Fi connection) · segmentation results (100% PASS) · L3 diagram.

## 9. Common pitfalls

- Locking yourself out of OPNsense. Keep console access and an anti-lockout rule.
- Forgetting AD **Sites & Services subnets**, which makes clients authenticate against far-away DCs.
- Blocking the RPC dynamic range between users and DCs, which breaks GPO processing. Test `gpupdate` after every rule change.
- "Allow any" rules added "temporarily" and never removed. The matrix and a quarterly rule review stop that.
- PEAP-MSCHAPv2 without server certificate validation: evil-twin APs can harvest credentials.

## 10. Resume bullets (templates)

- Segmented a flat network into **6 firewall-enforced VLAN zones** (OPNsense) with a default-deny, documented rule matrix and DNS/egress filtering; verified with an automated nmap test suite (**N/N paths as expected**).
- Removed internet-exposed RDP and deployed an **AD-integrated remote-access VPN** (OpenVPN + NPS RADIUS + MFA) and a **WireGuard site-to-site** tunnel supporting cross-site AD authentication and DHCP relay.
- Implemented **certificate-based 802.1X (EAP-TLS) Wi-Fi** with an internal AD CS PKI and GPO autoenrollment, replacing a shared PSK and isolating guest traffic.

## 11. Interview talking points

- **"Users can't get Group Policy after the firewall change."** Check the AD port list, especially the RPC dynamic range, then firewall logs for denies from that client, then `gpresult` and `nltest`.
- **"Why EAP-TLS over PEAP?"** No passwords over the air, no credential harvesting by evil-twin APs, and devices are identified by certificate.
- **"How do you know segmentation works?"** Show the test matrix and results. "Configured" is not "verified".

## 12. AI-ready build prompt

```text
Act as a senior network & security engineer mentoring me on a homelab capstone.
Project: P6 Network Segmentation, Remote Access VPN & Enterprise Wi-Fi for fictional "Halden Distribution Ltd".
Lab: Proxmox [or Hyper-V] with VLAN-aware bridge, FW01 OPNsense (HQ), new FW02 OPNsense (warehouse),
ad.halden.internal DCs (DC01 .10, DC02 .11) running DNS + DHCP failover, FS01, WS01 (user), WS02 (PAW), LNX01, OPS01.
Target zones: V10 SERVERS 192.168.10.0/24, V20 WAREHOUSE 192.168.20.0/24 (behind FW02), V30 USERS 192.168.30.0/24,
V40 MGMT 192.168.40.0/24, V50 GUEST, V60 IOT, VPN pool 192.168.70.0/24.

Phase by phase:
0. Discovery, device zoning, a complete firewall rule matrix (include exact AD ports), change/migration plan.
1. OPNsense VLANs, aliases, rules from the matrix, DHCP relay to Windows DHCP (new scopes in the failover pair),
   AD Sites & Services subnets.
2. DNS/egress filtering (force DNS via DCs, block outbound 53/853/445/3389), Quad9/Unbound decision.
3. Remove RDP forward; OpenVPN road-warrior with RADIUS to NPS (group-based network policy), MFA via NPS extension
   for Entra MFA or OPNsense TOTP fallback; staff guide; access request process.
4. WireGuard site-to-site FW01<->FW02 with routing, rules and AD verification (nltest /dsgetsite).
5. AD CS Enterprise CA, templates, autoenrollment GPO, NPS EAP-TLS policy, wireless GPO, test with eapol_test.
6. Test-Segmentation script + expected.csv, log review, config backups to Git, L2/L3 diagrams.
For each phase: exact steps/commands, expected result, verification, screenshots, rollback.
Finish with README, management summary and resume bullets using my results. Start with Phase 0.
```
