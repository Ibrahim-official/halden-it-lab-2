# Runbook — Restore a Wazuh component

**Applies to:** SIEM01 (Wazuh manager + indexer + dashboard, Docker Compose) · **Severity:** SEV2
monitoring outage · **Owner:** IT / Systems
**Target:** get monitoring back without losing alerts, and be honest in the incident note about the
monitoring gap.

Why this matters: when the SIEM is down, the business is blind. The gap itself is an incident worth
recording, because any attack during it would have gone unseen.

## 0. First: what exactly is down?

```bash
cd /opt/wazuh
docker compose --env-file .env ps                 # which of the three containers is unhealthy?
docker compose --env-file .env logs --tail=80 wazuh.manager
docker compose --env-file .env logs --tail=80 wazuh.indexer
```

| Symptom | Likely cause | First move |
|---|---|---|
| Dashboard unreachable, manager healthy | Dashboard container or its cert | Restart the dashboard; check the cert paths |
| Indexer unhealthy / out of memory | SIEM01 RAM exhausted (P7 is the heavy project) | Power off other VMs, raise SIEM01 memory, restart the indexer |
| Manager unhealthy / will not start | A bad `local_rules.xml`, or a full disk | Validate XML, check `df -h`, restore the rules backup |
| Agents all disconnected | Manager down, or network/agent port 1514/1515 | Fix the manager first; agents reconnect automatically |
| "max virtual memory areas too low" | `vm.max_map_count` too low | `sysctl -w vm.max_map_count=262144`, make it persistent |

## 1. Restart safely (manager first, then indexer, then dashboard)

```bash
cd /opt/wazuh
docker compose --env-file .env restart wazuh.manager
docker compose --env-file .env restart wazuh.indexer   # wait ~60-90 s for the indexer to be ready
docker compose --env-file .env restart wazuh.dashboard
docker compose --env-file .env ps
```

The manager holds the events in its queue, so a short restart does not lose data. A long outage
means agents buffer locally only for a while — say so in the incident note.

## 2. If the manager will not start after a rules change

The most common self-inflicted cause is a malformed rules file (this is why `scripts/06` validates
XML first).

```bash
# Validate before touching anything:
python3 -c "import xml.dom.minidom; xml.dom.minidom.parse('/opt/wazuh/local_rules.xml'); print('OK')"
# Roll back to the backup taken by scripts/06:
docker exec <manager> cp /var/ossec/etc/rules/local_rules.xml.bak /var/ossec/etc/rules/local_rules.xml
docker compose --env-file .env restart wazuh.manager
```

## 3. If the indexer is the problem

- Confirm SIEM01 has enough RAM (`free -h`); P7 is the heaviest project and the indexer wants ~4 GB.
- Power off FS01/WS02/OPS01 while the indexer recovers; raise SIEM01's dynamic memory to 6-8 GB.
- Check disk: a full disk stops the indexer. Free space or roll the oldest indices.
- **Do not delete volumes to "fix" it** unless you accept losing the history; that is a last resort
  and is recorded.

## 4. Verify recovery properly

```bash
docker compose --env-file .env ps                        # all healthy
curl -k https://localhost:9200                            # indexer responds
# From the manager: are agents coming back?
docker exec <manager> /var/ossec/bin/agent_control -l | grep -c Active
```

Then confirm a **live** alert path, not just a live container: generate one benign event (a known
logon) and confirm it reaches the dashboard.

## 5. The monitoring-gap note (do this every time)

| Question | Fill in |
|---|---|
| Monitoring down from / to |  |
| What was not collected |  |
| Did any agent buffer and replay? |  |
| Any incident during the gap? |  |
| What prevented this from being noticed sooner? |  |

Add the outcome to the monthly security summary and, if the cause was capacity, add it to the
capacity record for P10.

## Rollback

Every step here is a restart or a restore from a backup file — all reversible. The one irreversible
action (deleting an indexer volume) is explicitly forbidden without a decision recorded in
`DECISIONS.md`, and is a last resort. Take a SIEM01 snapshot before any structural change.

> **Design note:** the P7 design intentionally runs a single SIEM node, so the SIEM is itself a
> single point of failure. That is an accepted, documented limitation for a lab of this size — a
> production design would add a second indexer node and an out-of-band health check that does not
> depend on SIEM01.
