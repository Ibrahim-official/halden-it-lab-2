# Runbook — Check DHCP failover health

**Applies to:** DC01 (or DC02) · **Time:** 3 minutes · **When:** weekly, and after any DC outage

## Why

DHCP is Tier 0: without an address, a client cannot reach the domain. DC01 and DC02 share one
scope in a 50/50 load-balance relationship. If the relationship has broken silently, the second
server will not answer for the first — and nobody notices until the day a DC is down, which is the
worst possible time to find out.

## Weekly check

```powershell
# 1. Is the relationship healthy?
Get-DhcpServerv4Failover | Format-List Name,State,Mode,LoadBalancePercent,MaxClientLeadTime,PartnerServer

# 2. How much of the scope has gone to each server? (should be roughly half each)
Get-DhcpServerv4ScopeStatistics -ScopeId 192.168.10.0 |
  Format-List ScopeId,Free,InUse,PercentageInUse

# 3. Are BOTH servers registered in AD as authorised DHCP servers?
Get-DhcpServerInDC

# 4. Is DNS being updated dynamically, with name protection on?
Get-DhcpServerv4DnsSetting -ScopeId 192.168.10.0
```

Healthy looks like: `State = Normal`, `Mode = LoadBalance`, both servers listed, and the DNS
setting showing `DynamicUpdates = Always` with `NameProtection = True`.

## If the state is not Normal

| State | Meaning | Action |
|---|---|---|
| `Normal` | Both partners serving | Nothing to do |
| `CommunicationInterrupted` | The partners cannot reach each other on TCP 647 | Check the network path and firewall between DC01 and DC02; the scope is still being served by one side |
| `Conflict` | A partner's configuration has drifted | Look at `Get-DhcpServerv4Failover -Name HQ-Failover`, compare the two servers' scope options, then reconcile the odd one out |
| `Init` / `Recovering` | Transitioning after an outage | Wait, then re-check; do not force it |

```powershell
# force a re-check without restarting anything
Get-DhcpServerv4Failover -Name HQ-Failover | Get-DhcpServerv4FailoverStatistics
```

## The test that actually proves it (run once per review)

1. Note a client's current lease and IP.
2. Power **DC01** off at the hypervisor.
3. On the client: `ipconfig /release` then `ipconfig /renew`.
4. Expected: the client gets a working address and lists **192.168.10.11** as its DHCP server,
   and logon and DNS still work.
5. Bring DC01 back, confirm the failover state returns to `Normal`, and record the result.

**Do not skip step 5.** If the relationship stays degraded after the partner returns, clients may
end up with leases neither server will renew.

## Rollback

No configuration is changed by this runbook — it is read-only except for the deliberate power-off
in the proving test, which is reverted by powering DC01 back on.
