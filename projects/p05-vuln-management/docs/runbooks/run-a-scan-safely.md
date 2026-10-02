# Runbook — Run a vulnerability scan safely

**Applies to:** LNX01 (scanner host, Greenbone CE) · **Duty:** IT / Systems · **Time:** 10 min setup, 1–2 h to scan
**Owner of the rule:** AGENTS.md rule **R1 — lab only**. Read this before you run anything.

## Why this runbook exists

A vulnerability scanner does not politely ask; it connects to every port on every host you give it
and probes for weaknesses. Pointed at the wrong address that is not a mistake, it is an incident —
and potentially a criminal offence. So the rule is absolute: **this scanner only ever targets the
Halden lab ranges** (`192.168.10.0/24`, `192.168.20.0/24`, `192.168.30.0/24`). The scripts enforce
this, and this runbook tells you how to run a scan without relying on your memory.

## 0. Before you start

- [ ] LNX01 is up and the scanner containers are running (`docker compose ps` in `/opt/greenbone`).
- [ ] You have snapshotted LNX01 if you are changing anything (`snap-p5-ph3-before`).
- [ ] The target list in `configs/p05-scan-scope.txt` is current — no host that is switched off, no
      address that has moved.
- [ ] You are **not** connected to any network other than the lab (no VPN to work, no tethering).

## 1. Confirm the scope file is lab-only (never skip this)

```bash
cd projects/p05-vuln-management
# Prints every target that will be scanned and aborts on the first address outside the lab ranges.
bash -c '. scripts/lib/labguard.sh; require_lab_target 127.0.0.1' ; echo "guard responded: $?"
```

The check above deliberately passes a bad address (`127.0.0.1` is not a lab range) so you can see the
guard refuse. Expect:

```
ERROR: target '127.0.0.1' is outside the Halden lab ranges (...). Refusing to scan. AGENTS.md rule R1.
```

Now validate the real scope file:

```bash
bash -c '. scripts/lib/labguard.sh; require_lab_file configs/p05-scan-scope.txt'
```

If that prints a list of `scope ok:` lines and exits 0, every target is inside the lab. **If any line
aborts, stop. Do not edit the guard to make it pass.**

## 2. Reach the web UI (through a tunnel, not the network)

The UI is bound to loopback on purpose. From a management host on the lab LAN:

```bash
ssh -L 9392:127.0.0.1:9392 <you>@192.168.10.30
# then browse http://127.0.0.1:9392
```

## 3. Start the scan

- In the UI: **Scans → Tasks → P5 scan servers → Start**. The weekly task runs itself on Sunday at
  02:00; start it manually only for a verification rescan or an ad-hoc check.
- Or, headless, from the scanner host:

```bash
# Lists the tasks and their target sets first, so you can see exactly what will be scanned.
GVM_PASSWORD=... gvm-cli --gmp-username admin --gmp-password "$GVM_PASSWORD" \
  socket --socketpath /run/gvmd/gvmd.sock --xml '<get_tasks/>' | grep -E '<name>'
```

**Reminder:** if you create a task by hand in the UI, the target must come from a target set created
by `02-setup-targets.sh`. Do not type an IP address into the UI that you have not seen pass the guard
in step 1.

## 4. Watch it, then export the result

```bash
cd projects/p05-vuln-management
./scripts/04-export-report.sh          # newest finished report -> data/scans/latest.csv
```

The export writes the CSV the prioritizer reads, and archives the raw XML under `evidence/raw/`
(git-ignored). Then run the prioritizer:

```bash
python3 scripts/05-prioritize.py run \
  --findings data/scans/latest.csv \
  --assets   configs/p05-asset-criticality.csv \
  --enrichment data/kev-epss-cache.json \
  --rules    configs/p05-tier-rules.yml \
  --out-csv  reports/prioritized-work-list.csv
```

## 5. What "good" looks like

- Every task reports **finished**, not interrupted.
- The scan covers the host count you expect from `configs/p05-scan-scope.txt`. Fewer hosts than
  expected means host-down or a credential problem, not "we're clean".
- The prioritizer logs the funnel: findings in → deduplicated → tier counts. A scan that finds
  **zero** findings on a Windows server usually means the authenticated credential failed.

## 6. If something goes wrong

| Symptom | Likely cause | Action |
|---|---|---|
| A task scans nothing | target empty or host down | Check the host answers ping, then the target definition |
| Very few findings on Windows hosts | authenticated scan failed | Re-check the `svc-vulnscan` credential; unauthenticated results are shallow |
| Feed not synced | first sync takes hours | Wait; check `docker compose logs gvmd \| grep -i feed` |
| Guard aborts on a real host | the address is wrong | Fix the address in the scope file — do **not** widen the guard |

> **Lab practice:** this runbook is designed for the isolated lab. The guard tests in step 1 are
> deliberate: proving the guard *refuses* is as important as proving it allows. Do not claim a scan
> covered the lab until a real scan has run and its summary is captured in `evidence/public/`.
