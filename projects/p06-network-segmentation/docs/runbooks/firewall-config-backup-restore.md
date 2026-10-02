# Runbook — Back up and restore the firewall configuration

**Applies to:** FW01 and FW02 (OPNsense) · **Time:** 10 minutes · **Owner:** IT
**When:** before and after every firewall change, and monthly as a scheduled check

## Why this runbook exists

A firewall configuration is a single point of failure for the whole company, and it is a file. Losing
it means rebuilding a rule base from memory under pressure. Having it means a mistake costs ten
minutes instead of an evening — and that is the difference the business notices.

**One rule above all others: the export is never published.** An OPNsense export contains password
hashes, the API key, the RADIUS shared secret and VPN private keys. The raw file goes to
`evidence/raw/` (git-ignored); only the sanitised summary from the export script goes to Git or the
portfolio.

## 1. Take the export

```bash
# FW01
./scripts/12-Export-ConfigBackup.sh --host fw01

# FW02 (a copy of the same policy for the site-to-site side)
./scripts/12-Export-ConfigBackup.sh --host fw02
```

The script writes two files:

| File | Contents | Where it may go |
|---|---|---|
| `evidence/raw/p06-ph6-opnsense-config-fw01-<date>.xml` | The complete configuration, **with secrets** | Git-ignored. Never published, never attached to a ticket |
| `evidence/public/p06-ph6-config-summary-fw01.csv` | Counts only: interfaces, VLANs, rules, aliases, NAT entries, peers, users | Safe to commit |

Check the summary line for `nat_rules`: if inbound port forwards have reappeared, that is the finding
you were looking for — the RDP forward must not come back.

## 2. Store it safely

- Keep the raw export **outside the repository** as well: the owner's encrypted vault, or the backup
  repository (P8). A configuration you can only restore from a machine that just failed is not a
  backup.
- Record in the change record that an export exists and where it is — never the contents.
- In P9 this becomes automatic: the sanitised summary is committed nightly and a drift alert is
  raised when a change has no approved change record.

## 3. Restore it

1. **Log in on the console**, not the web UI — after a restore the web UI may be briefly unavailable,
   and if the restore is because you lost access, the console is your only route in.
2. **Confirm you are restoring to the right firewall.** FW01 and FW02 have different addresses and
   different rules; restoring the wrong one creates a very confusing afternoon.
3. **Restore:** OPNsense `System > Configuration > Backups > Restore`, select the export, and choose
   **Restore the configuration**.
4. **Reboot if prompted.** Then confirm the interfaces come up with their expected addresses.
5. **Re-apply nothing by hand.** The whole point of the export is that it is complete.

## 4. Prove the restore worked

Run the tests that belong to the firewall you restored:

```bash
sudo ./scripts/09-Test-Segmentation.sh --zone USERS-HQ     # on a workstation
sudo ./scripts/11-Test-GuestIotIsolation.sh --zone guest   # on a guest client
```

Then confirm the three things that matter most:

| Check | Expected |
|---|---|
| A client gets a lease and can sign in | Yes (relay and AD rules restored) |
| A guest cannot reach any `192.168.x` internal address | Yes (guest isolation restored) |
| RDP from the lab WAN is filtered, not open | Yes (no inbound forward) |

## 5. If the restore does not fix it

Work through the order of dependence — a firewall that looks wrong is often a *later* layer:

1. **Interfaces** — are the VLANs assigned and up?
2. **Rules** — does the deny log show the traffic being dropped, and by which rule number?
3. **Relay and DHCP** — is the client getting an address at all?
4. **AD** — if a client has an address but cannot sign in, suspect DNS or the AD port list before
   suspecting the firewall again.

**Rollback:** a restore is itself reversible — restore the previous export. Keep at least the last
three dated exports so there is always a known-good configuration to return to.
