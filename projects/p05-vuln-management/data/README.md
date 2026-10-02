# Synthetic input data

**Everything in this folder is synthetic.** These are invented findings for invented hosts belonging
to the fictional company Halden Distribution Ltd. They are **not** a scan of any real network, not
real customer data and not a real organisation (AGENTS.md rules R2/R3 and Section 4.6).

The CVE identifiers and CVSS base scores are real public identifiers and scores. Everything else —
which host has which finding, the synthetic KEV flags and the synthetic EPSS probabilities — is made
up to exercise every tier of the prioritisation model. **Do not read anything here as a claim about
the Halden lab or any real system.**

| File | What it is | Rows |
|---|---|---|
| `sample-scanner-export.csv` | A scanner export in the shape `scripts/05-prioritize.py` expects (`cve, cvss, host, service, port, title, solution, first_seen`). Includes two deliberate duplicate rows so the deduplication step is visible. | **51 data rows** |
| `asset-criticality.csv` | The asset inventory the prioritizer joins to (`host, role, os, exposure, criticality, owner, zone, notes`), in the format derived from the P1 lab hosts. | **10 assets** |
| `sample-enrichment.json` | A **synthetic stand-in** for the CISA KEV and FIRST EPSS feeds, so the sample run and the browser demo need no internet access and stay reproducible. | **17 CVEs** |
| `gen_sample_findings.py` | The generator that produced the two files above (deterministic, seeded with `seed=7`), so the dataset is reproducible rather than hand-written. | — |
| `gen_asset_inventory.py` | The generator that produced `asset-criticality.csv`. | — |
| `scans/` | Where the live scanner export lands (`latest.csv`) when `scripts/04-export-report.sh` runs. Empty until the first real scan. | — |

## How the sample is generated

```bash
cd projects/p05-vuln-management
python3 data/gen_asset_inventory.py
python3 data/gen_sample_findings.py
```

Both are deterministic: re-running them produces byte-identical files, which is why the row counts
above are stable and can be asserted by the unit tests.

## What the sample produces (a property of the sample, not a lab result)

Running the prioritizer over this sample (reference date 2026-10-02):

| Metric | Value |
|---|---|
| Scanner rows in | 51 |
| Unique findings after deduplication | **49** (2 duplicate rows removed) |
| P0 (emergency) | **2** |
| P1 (critical) | **7** |
| P2 (high) | **17** |
| P3 (medium) | **10** |
| P4 (low) | **13** |
| Urgent queue (P0 + P1) | **9 of 49 (18.4%)** |
| Findings with a CVE | 40 |
| Findings flagged KEV in the sample | 8 |
| Findings on the sample's internet-exposed hosts | 10 |

These numbers describe **the bundled synthetic sample only**. They are the input to the interactive
browser demo (`demo/index.html`) and are pinned by `scripts/tests/test_prioritize.py`. They are not
a measurement of the lab, and they must not be presented as one.

## Labelling requirement

Anywhere this data appears — a report, a screenshot, the website or the demo — it must be marked
**synthetic**. The syntax-only check: if a reader might think a number came from a real scan, the
label is missing.
