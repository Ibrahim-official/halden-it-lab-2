# Runbook — Restore the service desk database

**Applies to:** OPS01 (`192.168.10.40`) · **Time:** 20–40 minutes depending on size
**Owner:** IT / Systems · **Covers:** GLPI and BookStack databases and their files

## Why

The CMDB, the ticket history, the knowledge base and the documentation are the memory of the IT
function. Losing them means losing the audit trail of every change and every user's support
history. The nightly dump is only useful if a restore has been practised — an untested backup is
an assumption, not a control (the same principle as P8).

## 0. Before you start

- Snapshot OPS01 now (`snap-p9-ph1-before` or current) — a restore overwrites data.
- Know which dump you want: `ls -lh /opt/halden/backups/` (files are `glpi-db-<stamp>.sql.gz` and
  `bookstack-db-<stamp>.sql.gz`, each with a `.sha256`).
- Tell the business the desk will be read-only briefly; ideally do this out of hours.

## 1. Verify the dump before trusting it

```bash
cd /opt/halden/backups
sha256sum -c glpi-db-<stamp>.sql.gz.sha256      # integrity match
gzip -t glpi-db-<stamp>.sql.gz                  # gzip stream intact
```

If either fails, pick another dump. Do not restore an unverified file.

## 2. Stop the front ends (keep the database running)

```bash
sudo docker compose --env-file /opt/halden/.env -f /opt/halden/docker-compose.yml stop glpi bookstack
```

## 3. Restore the GLPI database

```bash
# Drop and recreate the schema, then load the dump.
docker exec -e MYSQL_PWD="$(grep -E '^GLPI_DB_ROOT_PASSWORD=' /opt/halden/.env | cut -d= -f2-)" \
  halden-glpi-db mariadb -uroot -e \
  "DROP DATABASE IF EXISTS \`$(grep -E '^GLPI_DB_NAME=' /opt/halden/.env | cut -d= -f2-)\`; \
   CREATE DATABASE \`$(grep -E '^GLPI_DB_NAME=' /opt/halden/.env | cut -d= -f2-)\`;"

gunzip -c glpi-db-<stamp>.sql.gz | \
  docker exec -i -e MYSQL_PWD="$(grep -E '^GLPI_DB_PASSWORD=' /opt/halden/.env | cut -d= -f2-)" \
  halden-glpi-db mariadb -u "$(grep -E '^GLPI_DB_USER=' /opt/halden/.env | cut -d= -f2-)" \
  "$(grep -E '^GLPI_DB_NAME=' /opt/halden/.env | cut -d= -f2-)"
```

Repeat the same pattern for BookStack using `BOOKSTACK_DB_*`, `bookstack-db-<stamp>.sql.gz` and the
`halden-bookstack-db` container.

## 4. Bring the front ends back and verify

```bash
sudo docker compose --env-file /opt/halden/.env -f /opt/halden/docker-compose.yml start glpi bookstack
```

- GLPI: log in and open **Assets** — the device count should match the CMDB before the incident, and
  a recent ticket should open with its history intact.
- BookStack: open a book and confirm its pages and revision history are present.
- Record the dump timestamp used and the time the desk was unavailable.

## 5. If the dump is from the wrong day, or there is none recent enough

That is a real gap and it is evidence for the backup design (P8): the restore point required was
older than the retention window. Raise it, note the required recovery point, and adjust the P8
schedule accordingly. Do not pretend the data is complete.

## 6. Rollback

Restoring is itself destructive (it overwrites the current database). If the restore makes things
worse, revert the OPS01 snapshot taken in step 0 and start again with the previous dump. Every
restore attempt should be logged with the dump used and the outcome.

> The restore has not been run yet: this is the procedure to follow when it is, and the result is
> recorded in `../../README.md` with a source file in `evidence/public/`.
