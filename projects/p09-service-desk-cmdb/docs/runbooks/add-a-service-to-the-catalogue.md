# Runbook — Add a new service to the catalogue

**Applies to:** GLPI (OPS01) and `business/p09-service-catalogue.md` · **Time:** 30 minutes
**Owner:** IT Manager (approval) then IT (implementation) · **When:** a new request type is needed

## Why

The service catalogue is a contract with the business: what IT offers, who approves it, and how long
it should take. It changes rarely and deliberately — every new service adds a form, an SLA target
and a line in the reports. Adding one ad hoc ("just give me a folder on the portal") is how catalogues
turn into chaos.

## 0. Before you start

- Snapshot: OPS01 container data volume (`snap-p9-ph2-before`); this changes GLPI configuration.
- Get the decision in writing: which service, who may request it, who approves, and the target time.
  If the request needs a new approval role, that is a business decision, not an IT one.
- If the new service has automation (for example "new starter" ties to P2), agree the handoff before
  wiring it up.

## 1. Add the service to the catalogue source

Edit `configs/glpi-service-catalogue.json` and add an entry with an id like `SRV-<NAME>`:

```json
{
  "id": "SRV-EXAMPLE",
  "name": "Example service",
  "description": "Plain-English description of what the requester gets.",
  "request_type": "Form",
  "approval": ["Line manager"],
  "target": "2 business days",
  "sla_priority": "P4",
  "linked_project": "P6"
}
```

Keep the list sorted by name and keep descriptions in plain English — users read these, not only IT.

## 2. Add or adjust the SLA target

If the target maps to an existing priority (P1–P4), no SLA change is needed. If it needs its own
target, edit `configs/glpi-sla-priorities.json`, add the priority (or a note), and — if the deadline
arithmetic changes — update the unit tests in `scripts/tests/test_sla.py` and run them:

```bash
python3 -m unittest discover -s scripts/tests -v
```

Only a change that the tests still prove correct should be applied.

## 3. Apply the configuration to GLPI

```bash
python3 scripts/03-configure_glpi_sla.py            # dry run: prints the payloads
python3 scripts/03-configure_glpi_sla.py --apply    # applies SLAs, priorities, business rules
```

Then create the matching self-service **form** in the GLPI UI (or in the catalogue plugin), with the
approval step and the target time shown to the requester.

## 4. Update the business documents

- Add the service to `business/p09-service-catalogue.md` (the human-readable catalogue).
- Add a row to the SLA policy if the target is new (`business/p09-sla-policy.md`).
- If the service needs escalation, note it in `business/p09-escalation-matrix.md`.
- Open the **change record** for the catalogue change (`business/p09-change-record.md` shape) — a
  catalogue change is a change even though it is "just" configuration.

## 5. Verify

- Submit the new form as a test user and confirm a ticket is created with the right category,
  priority and approval step.
- Confirm the requester sees the target time on the form.
- Delete the test ticket, or mark it closed as "test".

## 6. Rollback

Remove the catalogue entry from `configs/glpi-service-catalogue.json` and re-run the dry run, then
disable the form in GLPI. Existing tickets keep their category; the reports stay consistent because
the old category is retained, only hidden from new requests.

> Not yet run: the catalogue is designed and committed; the forms are created when the lab build
> reaches Phase 2, and the result is recorded in `README.md`.
