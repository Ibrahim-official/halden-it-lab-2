# Runbook — Add a device to a zone

**Applies to:** the lab hypervisor (the VLAN tag), FW01 (the zone already exists) and DC01 (DNS and
DHCP, if the device is dynamic) · **Time:** 20 minutes · **Owner:** IT Support

## Why this runbook exists

On a segmented network, "plug it in" is no longer a complete answer: the device needs the right VLAN
tag on the virtual (or physical) port, an address that comes from the right place, and rules that
deliberately let it do its job and nothing else. Doing this by habit is how a printer ends up on the
server VLAN.

## 1. Decide the zone before you touch the device

| The device is… | Zone | VLAN | Subnet |
|---|---|---|---|
| A server that holds company identity, data or certificates | SERVERS | 10 | 192.168.10.0/24 |
| A staff workstation or laptop | USERS-HQ | 30 | 192.168.30.0/24 |
| An administrative device (PAW, hypervisor, switch/AP management) | MGMT | 40 | 192.168.40.0/24 |
| A visitor device | GUEST | 50 | 192.168.50.0/24 |
| A printer, CCTV camera/DVR, warehouse scanner | IOT | 60 | 192.168.60.0/24 |
| A warehouse client at site 2 | WAREHOUSE | 20 | 192.168.20.0/24 |

If the device does not clearly belong somewhere, that is a decision, not a guess: use the design
document's zone model (`../00-design.md` §4) and, if it is genuinely new, raise it as a change.

## 2. Tag the port (hypervisor)

**Hyper-V** (per-VM NIC):
```powershell
# run on HOST01; -Access makes this an untagged (access) port on that VLAN
Set-VMNetworkAdapterVlan -VMName WS03 -Access -VlanId 30
Get-VMNetworkAdapterVlan -VMName WS03
```

**Proxmox** (VLAN-aware bridge): set the VM NIC's VLAN tag to 30 on the `vmbr1` trunk, or configure
the tag on the physical switchport for a real device.

**Physical access point or switch port:** set the port's native/access VLAN to match the zone. Guest
and IoT devices should never share a port with a corporate device.

## 3. Give it an address

- **Dynamic (USERS-HQ, WAREHOUSE, GUEST, IOT):** the FW01 relay forwards to the Windows DHCP pair for
  VLAN 20/30; OPNsense serves VLAN 50/60. Just verify the lease:
  ```powershell
  ipconfig /release ; ipconfig /renew ; ipconfig /all
  ```
  Check the address is in the zone's range, the gateway is the zone gateway, and DNS is
  `192.168.10.10, 192.168.10.11` — never an external resolver.
- **Static (SERVERS, MGMT, fixed IoT devices):** add the address to
  [`../../data/p06-zone-ip-allocation.csv`](../../data/p06-zone-ip-allocation.csv) so it is recorded,
  set it on the device, then create the DNS record.
  ```powershell
  Add-DnsServerResourceRecordA -Name "prn01" -ZoneName ad.halden.internal -IPv4Address 192.168.60.51
  ```

## 4. Check the rules it needs

The matrix already defines most cases (for example matrix rule 14 allows IOT → FS01 SMB for
scan-to-folder). If the device needs something new:

1. Do **not** add a broad allow. Identify the exact destination and port.
2. Add a numbered row to [`../../configs/p06-zone-rule-matrix.csv`](../../configs/p06-zone-rule-matrix.csv)
   with an owner and a justification.
3. Apply it using the ["apply a firewall rule change"](./apply-a-firewall-rule-change.md) runbook,
   including the snapshot, the config export and the test.

## 5. Prove it works

```bash
# from the new device (or a host in the same zone)
sudo ./scripts/09-Test-Segmentation.sh --zone <ZONE>
```

Then confirm the device can reach what it needs and **cannot** reach what it must not. For a guest or
IoT device specifically:

```bash
sudo ./scripts/11-Test-GuestIotIsolation.sh --zone guest   # or --zone iot
```

## 6. Record it

- Add the device to the zone/IP allocation table.
- If it replaced another device, update the CMDB (P9 owns the inventory).
- Close the ticket with what was changed, who approved the zone decision, and the test result.

**Rollback:** remove the VLAN tag (`Set-VMNetworkAdapterVlan -VMName X -Untagged`), release the lease
or remove the static record, and delete any rule you added through the change process. Nothing else
was changed.
