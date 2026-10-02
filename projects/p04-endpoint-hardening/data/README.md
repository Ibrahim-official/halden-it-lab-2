# Synthetic device fleet — P4 Windows 11 readiness

> ## Everything in this folder that describes devices is SYNTHETIC
>
> `synthetic-fleet.csv` is an **invented inventory of 150 machines** for the fictional company Halden
> Distribution Ltd. It is not a real inventory, the hostnames are not real machines, and no real
> personal data is used anywhere in this project (AGENTS.md rules R2 and R3, Section 4.6).
>
> Every count, percentage or chart derived from this file is a **synthetic-fleet figure** and must be
> labelled synthetic wherever it appears — in the business report, in the README and on the website
> page. The Windows 11 requirements the fleet is measured against are real; the fleet itself is not.

## Files

| File | What it is |
|---|---|
| `synthetic-fleet.csv` | 150 invented devices: `AssetID, Hostname, Department, Office, DeviceType, Model, CPU, CPUGeneration, RAM_GB, Disk_GB, TPMVersion, SecureBoot, UEFI, OS, OSBuild, DeviceAgeMonths`. Deterministic for a given seed. |
| `gen_synthetic_fleet.py` | The generator, so the dataset is reproducible and its randomness is verifiable rather than hand-faked. Also writes the summary file below. |
| `synthetic-fleet-summary.md` | Counts by status, by department and by failure reason — produced by the generator with plain arithmetic over the CSV, so no figure in this project is hand-typed. |
| `fleet_rules.py` | The Windows 11 readiness rules, shared by the generator, the analysis script and the unit tests so the three cannot disagree. |
| `synthetic-fleet-classified.csv` | Optional: written by `scripts/07-Get-Win11Readiness.ps1 -FleetCsv ...` when the fleet is classified with the PowerShell implementation. |

## How to regenerate (the exact file in this folder)

```bash
python3 data/gen_synthetic_fleet.py --count 150 --seed 42
```

`--seed 42` and `--count 150` reproduce this file byte for byte, which is what makes the counts in the
readiness report checkable: re-run the generator, re-read `synthetic-fleet-summary.md`, and the numbers
must match. `--dry-run` prints the summary without writing anything.

## How the data was designed

- **Scale:** 150 devices, chosen so the fleet is large enough for department-level analysis but small
  enough to check by eye. The fictional company has 85 staff plus shared devices.
- **Composition:** weighted like a distribution company — Operations/warehouse is the largest group,
  then Sales, then Finance — with shared kiosks and warehouse terminals assigned separately because
  they belong to no single team.
- **Hardware mix:** realistic device archetypes from a business estate: modern Windows 11 laptops and
  desktops, capable Windows 10 machines (8th and 9th generation Intel), and older machines that fail a
  Windows 11 requirement (7th generation and older, no TPM 2.0, no UEFI, or a thin client). The mix is
  deliberately not perfect: a real estate of this age never is.
- **Device age** is derived from the archetype (modern devices 6–30 months, older devices 60–108
  months) rather than being fully random, so the age column tells the same story as the hardware.

## What is real and what is not

| Real | Synthetic |
|---|---|
| The Windows 11 requirements (TPM 2.0, Secure Boot, UEFI, supported CPU, 4 GB RAM, 64 GB disk) | The 150 devices, their models, CPUs, ages and departments |
| The classification logic and the unit tests over it | The counts by status and by department in the readiness report |
| `scripts/07-Get-Win11Readiness.ps1`, which produces the same classification from real lab machines | The fleet-scale percentages and the cost-option arithmetic built on them |

## Labelling requirement (repeated on purpose)

Anywhere this data appears — a business report, a chart in a slide, a page on the portfolio website, a
README table — the words **synthetic fleet** must appear next to the figure. A number that looks like a
survey but is invented is exactly the kind of claim AGENTS.md rule R2 exists to prevent.
