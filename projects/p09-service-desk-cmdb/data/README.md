# Synthetic input data

**Everything in this folder is synthetic.** The people, tickets, serial numbers, prices and
suppliers are invented for the fictional company **Halden Distribution Ltd.** They are **not**
real customers, colleagues, devices or purchases, and no real personal information is used
anywhere in this project (AGENTS.md rules R2/R3/R6 and Section 4.6).

| File | What it is |
|---|---|
| `halden-assets.csv` | A synthetic CMDB asset inventory for import into GLPI and for the reconciliation and drift tests: **113 assets** — 45 laptops, 33 desktops, 6 servers, 8 printers, 9 network devices and 12 peripherals. Each row has a `Synthetic = yes` column. |
| `halden-tickets.csv` | A synthetic support-request export: **150 tickets over 4 simulated weeks**, generated deterministically (seed `20261002`). Every subject is prefixed `[SYNTHETIC]`. |
| `gen_synthetic_data.py` | The generator that produced both files, so the dataset is reproducible and its randomness is verifiable rather than hand-faked. Run `python3 gen_synthetic_data.py` to regenerate. |

## How it was generated

- `halden-assets.csv` is built in `gen_synthetic_data.py` with a fixed random seed (`7`); the
  counts per asset type are stated explicitly in the script (`plan`) rather than being random.
- `halden-tickets.csv` reuses the same deterministic generator that seeds GLPI
  (`../scripts/04-seed-synthetic-tickets.py`, seed `20261002`) so the committed sample and the
  GLPI simulation cannot drift apart. The generator's own correctness is covered by
  `../scripts/tests/test_seed.py`.

## Labelling requirement

Anywhere this data appears in a report, screenshot, dashboard or website page it must be marked
**"synthetic"**. The ticket volume, category mix and asset counts are a simulation used to exercise
the service desk and CMDB — they are **not** measurements of a real organisation, and no SLA
compliance, first-contact-resolution or reconciliation result is derived from them.
