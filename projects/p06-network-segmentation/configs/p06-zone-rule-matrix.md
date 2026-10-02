# P6 zone and rule matrix (readable form)

**What this is:** the ordered inter-zone firewall rule set for **FW01** (OPNsense, HQ), written so a
human can read it and an auditor can challenge it. The machine-readable copy is
[`p06-zone-rule-matrix.csv`](./p06-zone-rule-matrix.csv); both are generated from the same decisions
in [`../docs/00-design.md`](../docs/00-design.md).

**Where it applies:** FW01 only. FW02 (the warehouse firewall) has a single rule set: allow its
WireGuard peer and deny everything else, because all warehouse traffic that matters is destined for
the HQ SERVERS zone.

**How OPNsense evaluates it:** top down, **first match wins**. That is why the management-zone allow
(rule 1) sits above the management-zone deny (rule 22): a packet is judged by the first rule it hits,
not by the most specific rule in the list. Every rule carries its matrix number in its description so
a firewall log line points straight back to a documented justification.

**Default deny:** rule 24 denies and logs everything that reaches it. The matrix is the exception
list; the deny is the policy.

| # | Source zone | Destination | Service / ports | Action | Owner | Justification |
|---|---|---|---|---|---|---|
| 1 | MGMT | any internal | any | Allow | IT | Tier-0 administration from the PAW (WS02) only |
| 2 | USERS-HQ | SERVERS | DNS 53 | Allow | IT | AD name resolution through the DCs |
| 3 | USERS-HQ | SERVERS | Kerberos 88 | Allow | IT | AD authentication |
| 4 | USERS-HQ | SERVERS | kpasswd 464 | Allow | IT | Password change |
| 5 | USERS-HQ | SERVERS | LDAP/GC 389, 636, 3268, 3269 | Allow | IT | Directory lookups |
| 6 | USERS-HQ | SERVERS | SMB 445 | Allow | IT | SYSVOL/Netlogon and file shares |
| 7 | USERS-HQ | SERVERS | RPC 135, 49152–65535 | Allow | IT | Group Policy processing |
| 8 | USERS-HQ | OPS01 | HTTPS 443 | Allow | IT | Service desk / self-service |
| 9 | USERS-HQ | Internet | Web 80, 443 | Allow | IT | Business web access |
| 10 | VPN-USERS | SERVERS | AD + files (as rules 2–7) | Allow | IT | Remote-work parity with USERS-HQ |
| 11 | VPN-USERS | OPS01 | HTTPS 443 | Allow | IT | Service desk from home |
| 12 | WAREHOUSE | SERVERS | AD + files | Allow | IT | Cross-site authentication and files over WireGuard |
| 13 | WAREHOUSE | Internet | Web 80, 443 | Allow | IT | Web access at site 2 |
| 14 | IOT | FS01 | SMB 445 | Allow | Ops | Scan-to-folder only |
| 15 | IOT | SERVERS | DNS 53 | Allow | IT | Name resolution for scanners and cameras |
| 16 | GUEST | Internet | Web 80, 443 | Allow | IT | Internet-only guest access |
| 17 | any internal except DCs | Internet | DNS 53, 853 | **Deny** | IT | Force DNS via the domain resolvers so filtering and logging apply |
| 18 | any internal | Internet | SMB 445, RDP 3389 | **Deny** | IT | Remove the usual exfiltration and lateral-movement routes |
| 19 | GUEST | any internal | any | **Deny** | IT | Guest isolation from every company system |
| 20 | IOT | any internal | any | **Deny** | Ops | Beyond rules 14 and 15, printers and cameras need nothing |
| 21 | IOT | Internet | any | **Deny** | Ops | Only the FS01 SMB exception is granted |
| 22 | any | MGMT | any | **Deny** | IT | Management zone reachable only from MGMT itself |
| 23 | VPN-USERS | MGMT | any | **Deny** | IT | Remote staff must not reach the management zone |
| 24 | any | any | any | **Deny + log** | IT | Default deny |

## Notes an interviewer will probe

- **Rules 2–7 are one logical policy, "a domain client can talk to its domain".** They are split out
  because a single "any to SERVERS" allow would also expose SIEM01, BKP01 and CA01. The RPC dynamic
  range is the one most people forget, and forgetting it breaks Group Policy in a way that looks like
  a DNS fault.
- **Rule 7 can be narrowed** by pinning NTDS and Netlogon RPC to fixed ports on the DCs. That is a
  registry change with its own rollback, so it is written up as an option in the design document
  rather than done by default.
- **Rule 17 is the DNS-control rule.** Clients may only resolve names through `192.168.10.10` and
  `192.168.10.11`; a rogue-styled client that hard-codes a public resolver is redirected and logged.
  That is what makes DNS filtering and DNS logging meaningful.
- **Rules 22 and 23 are the least-privilege core.** A compromised user laptop, a compromised guest
  device and a compromised home laptop all fail to reach the management zone — which is where the
  hypervisor, the PAW and the infrastructure credentials live.
- **Rule 14 vs rule 20** is the IoT trade-off: a printer may write images to one share on FS01 and
  nothing else. Vendors ask for "internet for updates"; the answer here is a documented change
  request, not a permanent allow.

## Status

This matrix is **designed and reviewed, not yet applied**. The corresponding OPNsense rules and the
test results that prove the matrix behaves as written are captured in the lab phase and recorded in
[`../docs/as-built.md`](../docs/as-built.md) and [`../README.md`](../README.md). No rule here is
reported as working until the segmentation test suite has run.
