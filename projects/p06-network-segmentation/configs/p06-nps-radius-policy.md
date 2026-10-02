# P6 NPS / RADIUS policy definition

**What this is:** the designed NPS (Network Policy Server) configuration on **FS01** that provides
RADIUS to FW01 for two separate jobs — remote-access VPN authentication and Wi-Fi 802.1X
authentication. It is a definition, not an export: it is written down before the role is installed so
the policies can be reviewed against the security goal.

**Where it applies:** FS01 (RADIUS server, `192.168.10.20`). RADIUS clients are FW01 (VPN) and the
lab access point (Wi-Fi). The CA that issues the server certificate is CA01 (see
[`../scripts/07-Install-EnterpriseCa.ps1`](../scripts/07-Install-EnterpriseCa.ps1)).

**No secrets in this file.** The RADIUS shared secret is generated on the device (32 or more random
characters) and stored only in the owner's password manager and in FW01's own configuration. It is
never committed here, in a script argument, or in a chat log.

## 1. Role and registration

| Item | Designed value |
|---|---|
| Role | Network Policy and Access Services on FS01 |
| AD registration | `Register-ComputerAsRadiusClient` equivalent: NPS reads the domain so it can evaluate group conditions |
| Server certificate | Issued to `fs01.ad.halden.internal` from template `Halden-RAS-IAS-Server` |
| Accounting | Local log file plus Windows Security log (events 6272 granted, 6273 denied) |
| Shared secret | Generated on the device; **not in this repository** |

In production the RADIUS server would be a dedicated member server, and NPS on a domain controller is
a known Tier-0 risk. That trade-off is recorded in the design document rather than hidden.

## 2. RADIUS clients

| Client | Address | Purpose | Shared secret |
|---|---|---|---|
| FW01 (OpenVPN) | `192.168.10.1` | VPN authentication | Generated on device; vault only |
| Lab AP (802.1X) | `192.168.40.x` (management VLAN) | Wi-Fi authentication | Generated on device; vault only |

## 3. Network policies

| Policy | Order | Condition | Authentication | Result |
|---|---|---|---|---|
| `Wi-Fi-Corp` | 1 | NAS-Port-Type = Wireless AND a member of `G_WiFi_Devices` (or `Domain Computers`) | **EAP-TLS** ("Microsoft: Smart Card or other certificate") | Access-Accept; VLAN 30 assigned by the AP |
| `VPN-Staff` | 2 | Windows group `G_VPN_Users` AND NAS-Port-Type = Virtual | MS-CHAPv2 **inside a TLS tunnel** (OpenVPN) | Access-Accept |
| `VPN-IT-Mgmt` | 3 | Windows group `G_VPN_IT` | As `VPN-Staff` | Access-Accept with a Filter-Id / Class attribute that OPNsense maps to the MGMT route |
| `Defaults` | 99 | Any other | — | Access-Reject (explicit deny, so an unknown client is refused rather than ignored) |

**Why group-based conditions:** access is granted by AD group membership, so the joiner-mover-leaver
process in P2 is the single place where VPN and Wi-Fi rights are added and removed. Nobody edits an
NPS policy to give one person access.

**Why EAP-TLS for Wi-Fi:** there is no user password on the air and a device is identified by a
certificate the CA issued to it. An evil-twin access point has nothing to capture, which is the exact
weakness of PEAP-MSCHAPv2 without certificate validation.

## 4. Multi-factor authentication for VPN

| Option | When | Notes |
|---|---|---|
| NPS Extension for Microsoft Entra MFA | While a Microsoft 365 trial is active (P2 window) | Second factor is an Authenticator push; needs the tenant and licensing |
| OPNsense local TOTP (fallback) | Always available in the lab | Second factor is a one-time code; no cloud dependency |

Either way the README and the evidence must show a **second factor** prompting, not just a password.
The MFA configuration is a Phase 3 item; the trial-timing rule from the roadmap (start the M365 trial
only in the P2 window) still applies.

## 5. What is logged, and what the access review reads

- NPS event **6272** — access granted (who, when, which policy).
- NPS event **6273** — access denied, with a reason code (for example, not a member of the group).
- OPNsense VPN log — tunnel establishment and the assigned tunnel address.
- The quarterly access review in P2 reads these events against the current `G_VPN_Users` membership.

## 6. Validation plan (not yet run)

1. A user **not** in `G_VPN_Users` attempts a VPN login: expected Access-Reject, event 6273 with the
   reason code recorded.
2. A user in `G_VPN_Users` logs in: expected MFA prompt, then a tunnel, and access to FS01 but **not**
   the management zone.
3. A domain computer with autoenrolled certificate connects to `Halden-Corp`: expected EAP-TLS
   `SUCCESS` from `eapol_test` (see [`../scripts/10-Test-EapTls.sh`](../scripts/10-Test-EapTls.sh)).
4. A device without a valid certificate is rejected.

Every one of those results currently reads **not run**; the columns are filled from live output in
the lab phase, never in advance.
