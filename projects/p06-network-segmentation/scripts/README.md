# P6 scripts

Every script is lab-guarded (it refuses to run outside `ad.halden.internal` / a host carrying
`/etc/halden-lab`) and idempotent (safe to run twice). **Mode A** applies: the owner runs each
script against the lab; the agent never touches the home network, the home router or anything
outside the lab (AGENTS.md R1/R6).

| # | Script | Runs on | What it does | Changes state? |
|---|---|---|---|---|
| 00 | `00-Test-P6Preflight.sh` | any lab host | Read-only: checks every P6 config file exists, prints the zone/VLAN/rule plan, greps for secrets | No |
| 01 | `01-Apply-OpnSenseNetworks.sh` | owner, against FW01 | Creates VLANs, interface assignments, DHCP relay, aliases and the ordered rule set via the OPNsense API (or prints the GUI steps). Dry-run by default | Yes (with `--apply`) |
| 02 | `02-Set-WindowsDhcpScopes.ps1` | DC01 | Creates the USERS-HQ and WAREHOUSE scopes and adds them to `HQ-Failover` | Yes |
| 03 | `03-Set-AdSitesSubnets.ps1` | DC01 | Adds the new subnets to AD Sites and Services so clients pick a local DC | Yes |
| 04 | `04-New-NpsRadiusPolicy.ps1` | FS01 | Installs NPS, creates the VPN/Wi-Fi AD groups and the network policies; prints the GUI steps that touch secrets | Yes |
| 05 | `05-Configure-OpenVpnServer.sh` | owner, against FW01 | Removes the exposed RDP forward and configures the road-warrior VPN with RADIUS and a second factor | Yes (with `--apply`) |
| 06 | `06-Configure-WireGuardS2S.sh` | owner, against FW01/FW02 | Site-to-site WireGuard tunnel and the routing/rules around it | Yes (with `--apply`) |
| 07 | `07-Install-EnterpriseCa.ps1` | CA01 | Enterprise Root CA, certificate templates, autoenrollment GPO | Yes |
| 08 | `08-Configure-8021xWifi.ps1` | DC01 | Wireless GPO and the WLAN policy XML for the 802.1X SSID; PSK retirement steps | Yes |
| 09 | `09-Test-Segmentation.sh` | a host in each zone | Runs the segmentation test plan, writes the "N/N PASS" results CSV | No |
| 10 | `10-Test-EapTls.sh` | LNX01 | Validates the RADIUS/EAP-TLS path with `eapol_test` (works without an access point) | No |
| 11 | `11-Test-GuestIotIsolation.sh` | a GUEST and an IOT host | Proves guest and IoT isolation, including the one allowed IoT exception | No |
| 12 | `12-Export-ConfigBackup.sh` | owner, against FW01/FW02 | Exports the firewall config (git-ignored raw) and writes a sanitised summary for Git | No |
| — | `report/segmentation_report.py` | anywhere | Parses the results CSVs into a Markdown report and a verification matrix | No |
| — | `tests/test_segmentation_report.py` | anywhere | Unit tests for the report tooling (`pytest` or `unittest`) | No |

## Ordering rules

1. **Snapshot before every phase** (`snap-p6-ph<N>-before` on the VM(s) the phase touches).
2. **Never write a rule before the anti-lockout path exists.** Keep console access to the FW01 VM
   open while running script 01.
3. **Windows side before the firewall side where the firewall depends on it:** create the DHCP
   scopes (02) and the NPS policies (04) before enabling the relay and the VPN.
4. Test scripts (09–11) run **after** the configuration they test, never before.

## Secrets

WireGuard and OpenVPN private keys, RADIUS shared secrets and certificate private keys are generated
**on the device** and stored in the owner's password manager. They are never written to a file in
this repository, never passed as literals on a command line that gets committed, and never printed.
`configs/p06-certificate-plan.md` records exactly which certificate material may be committed.

## Tests

```bash
python3 -m pytest scripts/tests -q
# or, without pytest:
python3 -m unittest discover -s scripts/tests -t . -v
```
