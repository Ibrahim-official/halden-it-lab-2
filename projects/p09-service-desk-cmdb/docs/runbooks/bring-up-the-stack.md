# Runbook — Bring the OPS01 service desk stack up (and down)

**Applies to:** OPS01 (`192.168.10.40`) · **Time:** 15 minutes first time, 2 minutes after a reboot
**Owner:** IT / Systems · **Covers:** GLPI, Uptime Kuma, BookStack on Docker Compose

## Why

The service desk, the CMDB, the monitoring and the documentation all live in containers on OPS01.
If the host reboots, the containers must come back by themselves and the desk must not depend on
one person being awake. This runbook is how the stack is started, stopped and checked.

## 0. Before you start

- Snapshot OPS01 (`snap-p9-ph1-before`) the first time; not needed for a routine reboot.
- Confirm the git-ignored `.env` exists at `/opt/halden/.env` and contains **no** `CHANGE_ME`
  placeholders. Secrets live in the password manager, never in the repo or in chat.

## 1. Bring the stack up

```bash
sudo STACK_DIR=/opt/halden /opt/halden/../scripts/01-Deploy-ServiceDeskStack.sh   # reconciles containers
sudo docker compose --env-file /opt/halden/.env -f /opt/halden/docker-compose.yml ps
```

Expected: five containers — `halden-glpi-db`, `halden-glpi`, `halden-kuma`,
`halden-bookstack-db`, `halden-bookstack` — all `running`, with the two `-db` containers `healthy`.
The deploy script refuses to run if `.env` still holds placeholders.

## 2. Check each service

| Service | How to check | Healthy |
|---|---|---|
| GLPI | `curl -skI http://127.0.0.1:8080/` | HTTP 200/302, page loads |
| BookStack | `curl -skI http://127.0.0.1:8081/` | HTTP 200/302 |
| Uptime Kuma | `curl -skI http://127.0.0.1:3001/` | HTTP 200 |
| GLPI database | `docker exec halden-glpi-db healthcheck.sh --connect` | exits 0 |

In the Kuma UI every monitor should be green; the **Backup heartbeat** monitor is the one P8
depends on.

## 3. Take the stack down (planned maintenance)

```bash
sudo docker compose --env-file /opt/halden/.env -f /opt/halden/docker-compose.yml stop
```

This stops containers but **keeps volumes** (tickets, CMDB, docs). To start again, re-run step 1.
Never use `down -v` in normal operation: it deletes the named volumes.

## 4. If a container will not start

1. Read its log: `sudo docker logs --tail 100 halden-glpi`.
2. Database first: `halden-glpi` and `halden-bookstack` wait for their `-db` container to be
   `healthy`; a failing DB blocks them. Check `docker logs halden-glpi-db`.
3. Wrong credentials show as repeated "access denied" in the app log → re-check `/opt/halden/.env`
   against the values in the password manager.
4. Port already in use → another process holds 8080/3001; move the bind in `.env`
   (`GLPI_HTTP_BIND`, `KUMA_HTTP_BIND`, `BOOKSTACK_HTTP_BIND`) and re-run step 1.

## 5. Rollback

- **Stop only:** step 3, then start again when needed.
- **Bad upgrade:** pin the image tag back in `docker-compose.yml` (for example `glpi/glpi:10`),
  re-run step 1, then restore the database from the nightly dump if a migration ran badly
  (see the *restore the database* runbook).
- **Host broken:** revert the OPS01 hypervisor snapshot and re-run step 1.

> Nothing here is claimed as tested until the bring-up has actually been run in the lab and the
> result recorded in `README.md`.
