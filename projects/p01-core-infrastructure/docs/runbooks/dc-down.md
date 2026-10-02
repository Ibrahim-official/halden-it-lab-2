# Runbook — A domain controller is down

**Applies to:** DC01 or DC02 · **Severity:** Critical (Tier 0) · **Owner:** IT / Systems
**Target:** keep the business running first, diagnose second.

## 0. First 60 seconds — what to check and say

| Question | Command (from any domain-joined PC) | Expected healthy answer |
|---|---|---|
| Is the other DC answering? | `nltest /dsgetdc:ad.halden.internal` | Names the surviving DC |
| Does AD name resolution work? | `nslookup -type=SRV _ldap._tcp.dc._msdcs.ad.halden.internal` | Records returned |
| Are clients still getting addresses? | `ipconfig /renew` on a client | Lease from the surviving DHCP partner |
| Is replication broken or just one server? | `repadmin /replsummary` (on the surviving DC) | Only the dead partner shows failures |

**What staff should notice:** nothing. Two DCs with AD-integrated DNS and DHCP failover exist
precisely so that one server being down does not stop logon, name resolution or addressing. Say
that to the business, then investigate.

## 1. If DC01 is down

1. **Confirm the impact is contained** using the checks above. Clients should be resolving through
   DC02 (each DC's NIC lists its peer first, itself second).
2. **Do not restart the whole network.** Reboot the failed DC once, cleanly (console, not a power
   cycle), and watch the boot.
3. **On DC02, take over the FSMO roles** only if DC01 will be unavailable for a long time:
   ```powershell
   Move-ADDirectoryServerOperationMasterRole -Identity DC02 `
     -OperationMasterRole SchemaMaster,DomainNamingMaster,RIDMaster,PDCEmulator,InfrastructureMaster
   ```
   Note in the ticket that the roles have moved — they must be moved back deliberately later.
4. **Time:** the PDC emulator is the domain time source. Until DC01 returns, point DC02 at the
   external NTP peer so Kerberos keeps working:
   ```powershell
   w32tm /config /manualpeerlist:"time.windows.com,0x8" /syncfromflags:manual /reliable:yes /update
   Restart-Service w32time
   ```
5. **Recover DC01** from its last hypervisor checkpoint only as a last resort — reverting a DC
   snapshot can disturb replication. Prefer fixing the fault forward. Record the decision.

## 2. If DC02 is down

1. Confirm clients still authenticate and lease (same checks). DC01 continues to serve everything.
2. Reboot DC02 cleanly and watch it re-establish replication:
   ```powershell
   repadmin /showrepl DC02
   ```
3. No FSMO change is needed — all roles are on DC01.
4. If DC02 will be off for a while, check the DHCP failover relationship shows the partner in a
   degraded but serving state, and confirm leases are still being issued:
   ```powershell
   Get-DhcpServerv4Failover | Format-List Name,State,Mode,PartnerServer
   ```

## 3. When both are down, or the domain will not start

1. **Message the business immediately** — this is a full outage. Give an honest time estimate.
2. Boot the DC that failed most recently (or the one with the most recent backup) first, in
   **Directory Services Restore Mode** if needed.
3. Only restore a DC from backup when the problem is data corruption or a bad object change; a
   restore of one DC is safe as long as **the other DC is healthy and has replicated recently**
   (authoritative vs non-authoritative restore matters — decide before you act).
4. After service is restored, **verify replication, time, DNS records and DHCP leases**, then write
   a short incident note using the template in `docs/incident-note-template.md`.

## 4. Afterwards

- Record: start time, detection, what broke, what fixed it, user impact, and one prevention action.
- If the cause was DNS or time (the two most common), add a check to the weekly routine.
- P7 turns this manual diagnosis into monitored alerts; until then, the notes are the evidence.

> **Lab practice:** this runbook was written to be the routine for the two-DC design. The outage
> test (power DC01 off, keep signing in and renewing leases) is an acceptance test for P1 — see
> `README.md`. Do not claim it passed until the test has actually been run.
