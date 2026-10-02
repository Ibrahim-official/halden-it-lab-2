# P6 — Phase 0: Design document (segmentation, remote access and Wi-Fi)

**Project:** P6 Network Segmentation, Secure Remote Access VPN and Enterprise Wi-Fi
**Company:** Halden Distribution Ltd. (fictional, 85 users) · **Domain:** `ad.halden.internal`
**Status:** Phase 0 complete · **Owner:** Muhammad Ibrahim Akmal · **Mode:** A (Advisor)
**Spec:** [`docs/plan/P06-network-segmentation-vpn-wifi.md`](../../../docs/plan/P06-network-segmentation-vpn-wifi.md)

> Why design first: this is the change most likely to break everything at once. A firewall rule set
> written directly into the GUI has no review, no justification and no rollback plan. Writing the
> zone model and the rule matrix first is what turns "we changed the firewall" into "we changed the
> firewall in this documented way, verified by this test, and we can reverse it in ten minutes".

---

## 1. Goal and scope

Halden's network is flat: guests, CCTV, printers, scanners, laptops and servers share one subnet;
the Wi-Fi password is written on the break-room wall; remote staff reach the file server through a
port-forwarded RDP. This project replaces all three with:

- **Six firewall-enforced zones** (plus a VPN pool) on OPNsense FW01, with **deny-by-default**
  between them and every exception written down with an owner and a reason.
- **Egress and DNS control**: DNS only through the domain controllers, outbound SMB and RDP blocked.
- **No inbound port forwards.** Remote access only through an **OpenVPN road-warrior** server
  authenticated by **NPS/RADIUS** against an AD group, with a **second factor**.
- A **WireGuard site-to-site tunnel** joining the warehouse firewall (FW02) to HQ, carrying DHCP
  relay traffic and AD authentication for site 2.
- **EAP-TLS 802.1X Wi-Fi** using an internal **AD CS** PKI, replacing the shared pre-shared key, and
  an **isolated guest SSID**.
- **Proof**, not assertion: an automated test suite that attempts every allowed and denied path from
  a host in each zone and records what actually happened.

Out of scope for P6: endpoint hardening (P4), patch management (P5), monitoring and detection (P7),
and the automated config-as-code pipeline (P9 — which picks up the firewall backups this project
starts producing).

## 2. Business context (why this exists)

One compromised laptop should not be able to reach the backup repository, the hypervisor and the
domain controllers. On a flat network it can. The same flat network lets a visitor's phone, a CCTV
camera that nobody patches and a warehouse scanner all talk to the file server.

**Market evidence:** exploitation of **edge devices and VPNs** was a leading growth vector in the
Verizon DBIR 2025, and exposed RDP remains one of the most common ransomware entry points
(`docs/plan/00-research-and-selection.md`, rows 3 and 21–25). Segmentation, an authenticated remote
access path and a certificate-based network are the direct responses to that evidence.

**Success = the measurable criteria** in the P6 plan: six zones live with default-deny between them,
100% of expected-deny paths blocked and 100% of expected-allow paths open in the test suite, no
inbound port forwards, a working site-to-site tunnel, EAP-TLS Wi-Fi with no staff PSK, DNS and
egress control in place, and the diagrams, IP plan, rule matrix and config backups committed.

## 3. Design principles

1. **Deny by default, allow by documentation.** Every allow rule exists in
   [`configs/p06-zone-rule-matrix.csv`](../configs/p06-zone-rule-matrix.csv) with an owner and a
   justification. There is no "temporary" rule without a number.
2. **Least privilege at the network level.** A user zone reaches the services a user needs, not "the
   server subnet". A guest zone reaches nothing internal. A management zone is reachable from the
   management zone only.
3. **The test is the proof.** Configuration is a hypothesis; the segmentation suite is the
   experiment. "Configured" is not "verified".
4. **Every change is reversible.** Snapshot and firewall config backup before each phase, with the
   backout written down (see [`business/p06-change-record.md`](../business/p06-change-record.md)).
5. **Secrets never leave the device.** WireGuard and OpenVPN private keys, RADIUS shared secrets and
   certificate private keys are generated on the device and stored in the owner's password manager
   (AGENTS.md R3). [`configs/p06-certificate-plan.md`](../configs/p06-certificate-plan.md) says
   exactly which certificate material may be committed.
6. **Honest limitations.** Every gap in this design is listed in §12 rather than left implicit.

## 4. Zone model, and why each zone exists

| VLAN | Zone | Subnet | Contains | Why it exists |
|---|---|---|---|---|
| 10 | **SERVERS** | 192.168.10.0/24 | DC01, DC02, FS01, LNX01, OPS01, SIEM01, BKP01*, CA01 | The systems that hold the company's identity, data and certificates. Everything else is untrusted relative to this zone. |
| 20 | **WAREHOUSE** | 192.168.20.0/24 | Site-2 clients behind FW02 | A physically separate site should not be an extension of the office subnet. It reaches AD and files across the tunnel and nothing else. |
| 30 | **USERS-HQ** | 192.168.30.0/24 | Staff workstations and laptops (WS01) | The largest and most commonly compromised zone. It gets the services a user needs — DCs, file shares, the service desk — and no administrative access. |
| 40 | **MGMT** | 192.168.40.0/24 | WS02 (PAW), hypervisor, BKP01*, switch and AP management | The zone that can change everything, so the fewest things live in it and only its own members can reach it. |
| 50 | **GUEST** | 192.168.50.0/24 | Visitor devices | Heat, water and unknown patching. Internet only, client isolation on. |
| 60 | **IOT** | 192.168.60.0/24 | Printers, CCTV DVR, warehouse scanners | Devices that cannot be hardened and are often vendor-managed. One allowed write path (scan-to-folder) and nothing else internal. |
| — | **VPN-USERS** | 192.168.70.0/24 | Remote staff | Remote work should get *user* parity, not *network* parity: it inherits the user rules and is explicitly denied the management zone. |

\* BKP01 (the backup repository) moves from the SERVERS zone into MGMT during this project, as
decided in the tailored roadmap: a backup that a compromised server can reach is not a backup. That
is a change to P8's design and is recorded as a deviation.

**Why a separate MGMT zone at all** — the question an interviewer will ask. Because the blast radius
of a compromised *user* device is a policy choice, and the choice here is that it cannot reach the
hypervisor, the PAW or the backup repository. Authentication alone does not achieve that: the
credentials an attacker holds after a successful phish are user credentials, and a user credential
that can reach the hypervisor management interface is a domain compromise waiting to happen.

## 5. Traffic the business needs between zones (the deliberate exceptions)

The rule matrix is the exception list; default deny is the policy. The flows the business actually
needs, and nothing more:

| Business activity | Flow | Why it is needed |
|---|---|---|
| Staff sign in and process policy | USERS-HQ → DCs: DNS, Kerberos, kpasswd, LDAP/GC, SMB (SYSVOL), RPC | Without the full port list — especially the RPC dynamic range — Group Policy silently fails in a way that looks like a DNS fault |
| Staff open department files | USERS-HQ → FS01: SMB 445 | The file service is the point of P1's shares |
| Staff raise tickets | USERS-HQ → OPS01: HTTPS | Service desk and self-service portal (P9) |
| Staff browse the web | USERS-HQ → internet: 80/443 | Ordinary business use |
| Remote staff work from home | VPN-USERS → the same set as USERS-HQ | Remote-work parity; the least surprising behaviour for a user |
| Warehouse staff sign in and open files | WAREHOUSE → DCs/FS01/OPS01 across the tunnel | Site 2 is a working site, not a read-only annexe |
| Warehouse clients get an address | VLAN 20 → DHCP relay on FW01 → DCs | Without the relay, site 2 needs its own DHCP server |
| Scan-to-folder | IOT → FS01: SMB 445 | The one genuine business need from the printer/scanner zone. Approved by Operations, not IT |
| Scanners and cameras resolve names | IOT → DCs: DNS 53 | Devices with hard-coded names still need resolution |
| Visitors check email / a map | GUEST → internet: 80/443 | The entire purpose of guest Wi-Fi |

Everything else — guests reaching anything internal, IoT reaching anything but that one share, any
service reaching the management zone, remote staff reaching the management zone, any client using an
external DNS resolver, any internal host opening SMB or RDP to the internet — is denied and logged.

**The one deliberate exception worth naming in an interview:** IT needs management access over the
VPN. That is *not* an "allow any" rule; it is a separate AD group (`G_VPN_IT`) and a separate NPS
policy (`VPN-IT-Mgmt`) that attaches a route/attribute for the MGMT zone. The exception has a name,
an owner and a review date, which is what stops exceptions becoming the rule.

## 6. Egress and DNS control

| Item | Decision | Reasoning |
|---|---|---|
| Client DNS | Clients use `192.168.10.10` / `.11` (the DCs) only; DNS to anywhere else is blocked and logged | Filtering and logging are meaningless if a client can choose its own resolver |
| Upstream resolution | The DCs forward to **Unbound on OPNsense**, which uses DNS-over-TLS to a malware-blocking resolver | One place to change forwarders, one place to add blocklists, and the traffic is encrypted off-network |
| Blocklists | Optional Unbound blocklists for ads/malware, kept upstream of AD | AD's own zones stay authoritative on the DCs |
| Blocked egress | DNS 53/853 to non-DCs, SMB 445, RDP 3389 | The two protocols most used for exfiltration and for calling home |
| Alternative considered | DCs forward straight to the malware-blocking resolver (simpler, one less hop) | Rejected as the primary design because it removes the single point where filtering and logging can be applied; documented here because it is a legitimate choice for a very small site |

## 7. Remote access design (VPN with MFA)

```
staff laptop ── OpenVPN (TLS, per-user certificate) ──▶ FW01
                                                          │  RADIUS
                                                          ▼
                                                    FS01 (NPS)
                                          condition: member of G_VPN_Users
                                                          │
                                              ┌───────────┴───────────┐
                                    Entra MFA ⇢ NPS extension      or  OPNsense TOTP
                                              └───────────┬───────────┘
                                                          ▼
                                            tunnel 192.168.70.0/24
                                            user parity, MGMT denied
```

| Decision | Choice | Why, and the trade-off |
|---|---|---|
| Protocol | OpenVPN road-warrior with per-client certificates | Mature, integrates with RADIUS through OPNsense, and the client-side story is simple for non-technical staff. WireGuard is the site-to-site choice because the workload is different |
| Authentication | Certificate **plus** RADIUS group check **plus** a second factor | One factor is a stolen password; two is a stolen password and a stolen phone |
| Second factor | Entra MFA via the NPS extension (when a trial is active), otherwise OPNsense TOTP | The lab must always have a working second factor; the cloud path is the production-shaped one |
| Tunnel scope | **Split tunnel**: only internal routes are pushed | Better bandwidth and less hair-pinning, at the cost of the endpoint's own internet posture not being controlled by us — which is why P4's endpoint baseline matters |
| Full tunnel (rejected) | All traffic through HQ | Simpler policy, but every home video call flows through a lab firewall; it is the right choice for high-sensitivity roles, not for all staff |
| Access request | Ticket → manager approval → added to `G_VPN_Users` → quarterly review | Access is a business decision; the P2 joiner-mover-leaver process is the only place membership changes |
| RDP exposure | Removed entirely | The port forward *was* the entry point. Removing it is the point of this phase, not a side effect |

## 8. Wi-Fi design (802.1X and guest)

| SSID | Security | VLAN | Who | Notes |
|---|---|---|---|---|
| `Halden-Corp` | WPA3-Enterprise (WPA2-Enterprise if the AP lacks WPA3), **EAP-TLS** | 30 (USERS-HQ) | Domain computers with an autoenrolled certificate | No password on the air; a device is identified by certificate |
| `Halden-Guest` | Open with a captive portal / voucher, client isolation on | 50 (GUEST) | Visitors | Internet only; reception issues the voucher |

```
CA01 (Enterprise Root CA)
   ├── template Halden-WiFi-Computer      → autoenrolled to domain computers  → Halden-Corp
   ├── template Halden-RAS-IAS-Server     → FS01 (NPS) so clients can validate the server
   └── (optional) Halden-VPN-Client       → remote-access certificates
```

| Question | Answer |
|---|---|
| Why EAP-TLS and not PEAP-MSCHAPv2? | There is no user password to capture with an evil-twin access point or to crack offline. The identity is a certificate the CA issued to that device |
| How is it tested without an access point? | `eapol_test` on LNX01 acts as the authenticator, presenting the client certificate to NPS and printing `SUCCESS` on an Access-Accept. That validates the RADIUS and PKI path; it does **not** validate a real AP, and the write-up says so |
| What retires? | The shared pre-shared key. Once every domain device has a certificate, the PSK SSID is switched off and the break-room wall password stops being a control |
| In production? | An offline root CA plus a separate issuing CA, and the CA treated as Tier 0 — see §12 |

## 9. Interface and rule placement summary

| Where | What lives there | Why |
|---|---|---|
| FW01 (HQ) | All six VLAN interfaces, the VPN pool, the DHCP relay, the whole matrix, the WireGuard peer to FW02 | One policy point at the HQ boundary; one place to review |
| FW02 (warehouse) | The VLAN 20 interface, one WireGuard peer, a two-rule policy (AD/file traffic to HQ, then deny) | Site 2 needs the tunnel, not a copy of the HQ matrix |
| OPNsense aliases | `DCs`, `FileServers`, `AD_PORTS`, `RFC1918`, the zone networks | Rules read as sentences; a subnet change is one edit instead of dozens |

**Ordering matters and is written into the script:** VLANs → interfaces and gateways → the MGMT
anti-lockout path → relay → aliases → rules. Writing rules before confirming you can still reach the
firewall is how people lock themselves out of their own network.

## 10. AD, DNS and DHCP consequences

| Item | Change | Why it matters |
|---|---|---|
| AD Sites and Services | Add `192.168.30.0/24` → HQ and `192.168.20.0/24` → WAREHOUSE | Without the subnet objects a client picks a DC on the other side of the tunnel and AD looks slow and unreliable |
| DHCP scopes | Two new scopes (USERS-HQ, WAREHOUSE) added to the existing P1 failover pair | One addressing service, two more networks, same resilience |
| DHCP relay | On FW01 for VLAN 20 and 30, forwarding to `192.168.10.10` and `.11` | Broadcasts do not cross a router; the relay makes them reachable |
| DNS | Unchanged zones on the DCs; forwarders move to OPNsense Unbound | Filtering happens upstream of AD; AD stays authoritative for its own namespace |
| GPO | `SRV - Remote Management - v1` narrows its `IPv4Filter` from `192.168.10.*` to the MGMT subnet | A rule that made sense on a flat network becomes a hole on a segmented one |

## 11. Build phases and evidence plan

Evidence naming follows AGENTS.md 4.5 (`p06-phN-<what>-<result|before|after>.<ext>`).

| Phase | Deliverable | Evidence to capture |
|---|---|---|
| 0 | This design, the rule matrix, the IP plan, the change record | The documents themselves |
| 1 | VLANs, interfaces, relay, aliases, rules on FW01; new DHCP scopes; AD subnets | Interface list, rules showing the matrix numbers, a client getting a lease in its new zone |
| 2 | DNS and egress filtering | `nslookup` to an external resolver timing out; resolution through the DCs working; the redirect logged |
| 3 | RDP forward removed; VPN with RADIUS and MFA | Scan of the lab WAN showing RDP filtered rather than open; NPS 6272/6273; an MFA prompt; MGMT unreachable over the tunnel |
| 4 | WireGuard site-to-site | A handshake on both peers; a warehouse client with a lease, `nltest /dsgetsite` returning `WAREHOUSE`, and a mapped drive |
| 5 | AD CS, templates, autoenrollment, NPS EAP-TLS, wireless GPO | `certutil -store My` on a client; `eapol_test` result; a guest client unable to reach any internal address |
| 6 | Segmentation suite, guest/IoT isolation, config backups, final diagrams | The results CSVs in the `N/N PASS` shape, the sanitised config summary, the L2/L3 diagrams |

## 12. Honest limitations

| Limitation | Why it is acceptable here, and what production would do differently |
|---|---|
| The CA is a single Enterprise Root CA on one VM | Cheap and sufficient for a lab. Production: offline root plus issuing CA, both Tier 0, with HSM-backed keys |
| NPS runs on FS01, a member server, rather than a dedicated host | Deliberate: NPS on a **domain controller** is the common shortcut and it enlarges the Tier-0 attack surface. In production, a dedicated RADIUS pair |
| The lab's WAN is the Hyper-V Default Switch (NAT) | The lab must never expose anything to the internet (AGENTS.md 5.1). Consequences: the "external scan" evidence is a scan from the NAT side, and the findings are described as what they are — no public address is ever recorded |
| Split tunnel leaves the endpoint's own internet path uncontrolled | Mitigated by P4's endpoint baseline, not by the VPN. Full tunnel is the alternative and its trade-off is documented in §7 |
| The warehouse has no local DC or RODC | If the tunnel is down, site 2 cannot authenticate. Plan-accepted for the lab; production would place an RODC at a site that must survive a WAN outage |
| RPC dynamic range is left at 49152–65535 | Narrowing it needs registry changes on the DCs with their own rollback; offered as an option rather than done silently |
| IoT vendors ask for "internet for updates" | The answer is a change request with a named vendor host, not a permanent allow. Until that exists, IoT has one internal write path and no internet |
| 802.1X is validated with `eapol_test`, not always with a real access point | `eapol_test` proves the RADIUS and certificate path; the AP proves the wireless configuration. The write-up states which one was actually done rather than implying both |
| Wi-Fi security depends on the access point's capabilities | If the AP is WPA2-only, WPA2-Enterprise is used and the degradation is documented rather than hidden |

## 13. Snapshot, backup and rollback plan

- **Before every phase**, snapshot each VM the phase touches: `snap-p6-ph<N>-before`
  (for example `snap-p6-ph1-before` on FW01 and both DCs).
- **Before touching any firewall rule**, export the FW01 configuration with
  [`scripts/12-Export-ConfigBackup.sh`](../scripts/12-Export-ConfigBackup.sh). That export is the
  primary backout: restoring it returns the entire rule set, not just the rule you just added.
- **Keep console access to the FW01 VM open** during every firewall change, and never remove the
  anti-lockout path. A firewall you cannot reach is an outage, not a change.
- **Regular VMs (FS01, WS01, guests):** revert the snapshot. **Domain controllers:** fix forward
  where possible — reverting a DC snapshot can disturb replication (the same caution as P1).
- **If the firewall locks you out:** restore the console, apply the most recent config backup, and
  re-run the phase scripts, which are idempotent.

## 14. Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Locking yourself out of FW01 | Medium | High | Anti-lockout rule, console access kept open, config backup before every change |
| Group Policy breaks after the rule change | Medium | High | Complete AD port list including the RPC range; `gpupdate` after every rule change; firewall logs reviewed for unexpected denies |
| Users cannot reach a service nobody remembered | Medium | Medium | The test suite defines the allowed paths up front; the matrix has an owner per rule; the change record carries a comms plan |
| DHCP relay misconfigured → clients get no address | Medium | High | Relay tested per zone before moving the next zone; verify a lease in every zone as part of Phase 1 |
| M365 trial expires before the MFA extension is finished | Medium | Medium | TOTP fallback always works; the trial timing rule from the roadmap is followed |
| Wireless AP unavailable or WPA2-only | Medium | Low | `eapol_test` validates the RADIUS/PKI path; WPA2-Enterprise documented as the fallback |
| Snapshot revert on a DC causing replication issues | Low | High | Fix forward on DCs; the caution is repeated in the runbook |
| 16 GB host cannot run every VM plus FW02 | Medium | Low | Run only the VMs the phase needs (AGENTS.md: that is what keeps the lab inside 16 GB) |

## 15. Interview notes (Phase 0)

**"Why deny by default with documented exceptions, rather than a long allow list?"** Because the
allow list is the security policy and the deny is the safety net. A long allow list tells you what is
permitted today; a default deny with named, owned exceptions tells you the same thing *and* fails
closed when somebody forgets to add a rule. It also makes the question "why is this allowed?" have a
written answer with a person's name on it.

**"How do you know segmentation works?"** I don't assume it — I run a test suite that attempts every
allowed and denied path from a host in each zone and records what happened. "Configured" is not
"verified". The results are the deliverable, not the rule list.

**"I need a quick exception — can you open this port?"** Yes, through the front door: a ticket, a
justification, an owner, a rule number in the matrix and a review date. What I will not do is add an
"allow any" rule that nobody removes. If the request is genuinely urgent, the time-boxed rule still
gets a number and an expiry, because "temporary" rules that are not written down are how a rule base
rots.

---

*Next step: Phase 1 — VLANs and inter-VLAN routing on FW01 (plan §Phase 1). Snapshot FW01 and the
DCs, export the current firewall configuration, and keep console access open. Mode A: the owner runs
the scripts against the lab firewall and pastes the output back.*
