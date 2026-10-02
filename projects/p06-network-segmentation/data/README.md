# P6 support data

Everything here is **designed data for the fictional company Halden Distribution Ltd.**, not a
measured result and not real personal information (AGENTS.md R2/R3). The staff and device names are
invented; the addresses are lab-private `192.168.x` ranges.

| File | What it is | Used by |
|---|---|---|
| `p06-segmentation-test-plan.csv` | The defined list of connections that must be **allowed** and must be **blocked**, per zone and per rule-matrix entry. **This is a template: it holds expectations, not results.** | `../scripts/09-Test-Segmentation.sh` |
| `p06-zone-ip-allocation.csv` | One row per address in the segmented lab: zone, VLAN, subnet, host, role, address, addressing method. | `../scripts/00-Test-P6Preflight.sh`, the architecture diagram, the business zone matrix |

## How results relate to this folder

The test plan is the **contract**: it says what the firewall rules are supposed to do. The **evidence**
lives in `../evidence/`, never here:

- `scripts/09-Test-Segmentation.sh --zone <ZONE>` writes
  `evidence/raw/p06-ph6-segmentation-results-<host>.csv` and a sanitised copy in `evidence/public/`.
- `scripts/11-Test-GuestIotIsolation.sh` writes the guest/IoT isolation results the same way.
- `scripts/report/segmentation_report.py` turns those files into a report and a verification matrix.

Before the lab run those evidence files do not exist, so the report tool prints "No results yet".
That is the correct output: **this project never publishes a number it has not measured.** The plan
file therefore carries no `actual` or `pass` column, because those columns would invite exactly the
fabrication the rules forbid.

## How to read the test plan

- `source_zone` is the zone the test host is in. At run time you pass `--zone ZONE`, and the suite
  runs only the rows for that zone: a USERS-HQ workstation cannot honestly test guest isolation.
- `expected` is `open` or `blocked`. A `blocked` row passes when the port is **closed, filtered or
  unreachable** (a firewall rule looks like one of those three from the outside); an `open` row
  passes only when the port is genuinely **open**.
- Destinations are `192.168.x` lab addresses only. The suite refuses a plan containing anything
  else, so it can never probe the home network or the internet (AGENTS.md R1).

## Why a test host per zone is needed

Running the suite from inside the firewall would prove nothing about what a user experiences, and it
would bypass the very rules being tested. The plan is designed to be run from: WS01 (USERS-HQ), a
warehouse client (WAREHOUSE), WS02 (MGMT), a guest VM temporarily placed in VLAN 50, an IoT test
client in VLAN 60, and a VPN client connected through the tunnel.
