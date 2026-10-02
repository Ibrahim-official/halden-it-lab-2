# Windows 11 readiness report — Halden device fleet

**Prepared for:** Managing Director and Finance Director
**Prepared by:** Muhammad Ibrahim Akmal, IT · **Date:** 2026-10-02
**Supporting data:** `data/synthetic-fleet.csv` and `data/synthetic-fleet-summary.md`
**Companion documents:** `p04-exec-brief.md`, `p04-endpoint-standard.md`

---

> ## ⚠ This fleet is SYNTHETIC
>
> Halden is a fictional company and this report is a home-lab portfolio artefact. The device fleet
> described below is an **invented inventory of 150 machines**, generated deterministically to
> demonstrate a real readiness method. It is **not** a survey of real hardware, and no real device was
> measured. Every count in this report is a plain count of that synthetic file, produced by
> `data/gen_synthetic_fleet.py`, and is labelled as a synthetic-fleet figure throughout.
>
> The *Rules* and the *method* are real: they are the actual Windows 11 requirements and the actual
> classification logic that `scripts/07-Get-Win11Readiness.ps1` applies to real machines.

---

## 1. Executive summary

The synthetic fleet contains **150 devices**. Under the Windows 11 requirements:

| Status | Devices | Share of fleet |
|---|---:|---:|
| `ready` — capable and already on Windows 11 | 78 | 52% |
| `upgrade` — capable hardware still on Windows 10 | 41 | 27% |
| `replace` — a hardware requirement is not met | 31 | 21% |

*(Synthetic-fleet figures. Counts derived directly from `data/synthetic-fleet.csv`; shares are simple
arithmetic on those counts.)*

The practical reading: roughly half the fleet needs nothing, roughly a quarter can be moved to Windows
11 with an in-place upgrade, and roughly a fifth cannot run Windows 11 at all and needs replacing. The
Windows 10 population as a whole — devices needing an upgrade or a replacement — is **72 of 150
devices (48%)**. Those devices currently receive no security updates from Microsoft.

**Recommendation:** Option A. Upgrade the 41 capable devices in place, and replace the 31 incapable
devices to a schedule. It has the lowest ongoing risk and the fewest moving parts. Option B (Extended
Security Updates as a bridge) is a fallback if the capital spend cannot be released this year, and it
must be understood as a delay, not a solution. Option C is not a plan — it is accepting an unpatched
estate.

## 2. Why this matters (business context)

- Windows 10 reached end of support on **14 October 2025**. Devices that remain on it receive no
  security fixes.
- Industry data shows about **21% of small-business Windows devices were still on Windows 10 in
  mid-2026** (Lansweeper, reported by Computer Weekly). Halden's synthetic 48% is worse than that
  average, which is exactly why the question is being asked now rather than next year.
- Microsoft's commercial **Extended Security Updates** run for at most three years and must be paid for
  each year, and the annual price rises. ESU buys time; it does not remove the need to move.
- **Ransomware is the main risk for a business this size**, and it starts on endpoints. An unsupported
  device is the easiest place for it to start.
- Insurance and customer due-diligence questionnaires increasingly ask about the operating system
  lifecycle. "We are working on it" is a weaker answer than a dated plan.

## 3. Method

1. The Windows 11 requirements were written down once (`configs/win11-readiness-rules.yaml`): TPM 2.0,
   Secure Boot, UEFI firmware mode, a supported CPU (Intel 8th generation / AMD Zen+ or newer), at least
   4 GB RAM and at least 64 GB system disk.
2. The same rules were implemented once in code (`data/fleet_rules.py`), used by the generator, the
   analysis script and the unit tests, so the three cannot disagree.
3. The synthetic fleet was generated deterministically (`data/gen_synthetic_fleet.py --count 150 --seed 42`),
   so anyone can reproduce the exact file and the exact counts.
4. Devices were classified: any unmet hardware requirement means `replace`; all met and still on
   Windows 10 means `upgrade`; all met and already on Windows 11 means `ready`.
5. The live inventory script (`scripts/07-Get-Win11Readiness.ps1`) applies the same logic to real lab
   machines, so the method is proven on hardware and only the fleet scale is synthetic.

## 4. Fleet status in detail (synthetic fleet)

### 4.1 By status

| Status | Devices | Share | What it means for the business |
|---|---:|---:|---|
| `ready` | 78 | 52% | No action. These devices are already compliant with the standard. |
| `upgrade` | 41 | 27% | An in-place upgrade on a schedule; a short per-device disruption. |
| `replace` | 31 | 21% | These cannot run Windows 11 and must be replaced to keep receiving security updates. |

### 4.2 By department

| Department | ready | upgrade | replace | Total |
|---|---:|---:|---:|---:|
| Finance | 11 | 5 | 4 | 20 |
| HR | 5 | 1 | 3 | 9 |
| IT | 10 | 3 | 1 | 14 |
| Management | 10 | 5 | 3 | 18 |
| Operations (incl. warehouse) | 24 | 19 | 10 | 53 |
| Sales | 18 | 8 | 8 | 34 |
| Shared / kiosk | 0 | 0 | 2 | 2 |
| **Total** | **78** | **41** | **31** | **150** |

*(Synthetic-fleet figures. The department split is part of the generated data, adjusted so that shared
kiosks and warehouse terminals belong to no single team.)*

### 4.3 Why devices are classified `replace` (synthetic fleet)

| Hardware requirement not met | Devices affected |
|---|---:|
| CPU older than Intel 8th generation / AMD Zen+ | 31 |
| TPM 2.0 missing or disabled | 10 |
| Legacy BIOS (no UEFI firmware mode) | 8 |
| Secure Boot not enabled | 8 |

A device can fail more than one requirement, so these counts add up to more than the 31 `replace`
devices — which is the useful detail for planning, because a machine failing only the CPU check and one
failing the TPM check need the same answer (replace), but the cause tells you how old the estate is.

### 4.4 Where the risk is concentrated

- **Finance (4 of 20 devices) and Management (3 of 18)** include a higher proportion of older hardware.
  These are the devices most likely to hold sensitive data, so they should be replaced first.
- **Operations/warehouse (10 of 53)** carries the largest number of incapable devices, including shared
  terminals and thin clients. These are the least personal and easiest to swap in a batch.
- **Shared kiosks (2)** are both incapable and are shared machines logging into shared accounts, so they
  are the quickest, cheapest replacements.

## 5. Options for management

All three options cover the same 72 devices that currently receive no security updates (41 to upgrade,
31 to replace).

**Cost note:** the labour figures are planning estimates from the project's upgrade runbook, and the
device and ESU figures are **placeholders** until a current vendor quote and the current Microsoft ESU
price are attached. The report must state the quote date before it is used for a budget decision.

| Option | What it involves | Indicative cost | Risk | Ongoing position |
|---|---|---|---|---|
| **A. Upgrade and replace (recommended)** | Upgrade the 41 capable devices in place this quarter; replace the 31 incapable devices over the next two quarters, Finance and Management first | Labour for 72 devices + 31 × device cost | **Lowest.** Ends the unsupported estate on a dated plan | A fully supported fleet within two quarters |
| **B. Upgrade, then ESU as a bridge** | Upgrade the 41 capable devices now; buy Extended Security Updates for the 31 incapable devices for one year and replace them next financial year | Labour for 41 devices + ESU year 1 + 31 × device cost later | **Medium.** ESU price rises each year and covers only three years; it delays, it does not remove, the spend | Still ending with a replacement programme, but a year later and at a higher total cost |
| **C. Do nothing** | Continue as today | No new spend now | **High.** Unpatched operating systems, uncontrolled data on unencrypted portable devices, and a question the business cannot answer in a due-diligence questionnaire | No date on which the estate becomes supported |

### 5.1 Why Option A is recommended

- It is the only option that ends with the problem solved rather than deferred.
- Replacing the oldest devices first removes the machines least able to run modern security controls —
  several have no TPM 2.0 at all, which means no BitLocker and no Credential Guard either, so they
  weaken the endpoint standard as well as the patch position.
- The work is predictable: an upgrade per device is a short, repeatable task with a runbook, and
  replacements can be batched by department.

### 5.2 If Option B is chosen

Be explicit with the business about the trade: ESU is a **bridge**, not a plan. It is a defensible
choice if capital cannot be released this year, provided the replacement programme is approved at the
same time with a date, so the bridge has something on the other side.

## 6. Recommended plan and timeline

| Phase | Weeks | Work | Owner |
|---|---|---|---|
| 1 | 1–2 | Approve Option A and the replacement budget; confirm vendor quotes and the ESU price for reference | MD + FD |
| 2 | 1–2 | Replace the 4 Finance and 3 Management incapable devices first | IT + Finance |
| 3 | 3–6 | In-place upgrade the 41 capable devices in department batches, using the upgrade runbook | IT |
| 4 | 3–6 | Replace the remaining 24 incapable devices (Operations/warehouse batch first, then Sales) | IT |
| 5 | 7 | Confirm the whole fleet passes the daily endpoint check; close the programme with a short report | IT |

## 7. Risks and dependencies

| Risk | Mitigation |
|---|---|
| A critical business application does not work on Windows 11 | Test the specific applications a user runs during the upgrade pilot, not the full installed list; the upgrade runbook has a rollback window |
| Replacement hardware lead times slip | Order the Finance and Management devices first, since they carry the most sensitive data |
| Users are disrupted during the upgrade | Batches by department, agreed dates, upgrades done around work, and a rollback available for ten days |
| ESU price or eligibility is different from the placeholder | Confirm the current Microsoft price and eligibility before any Option B decision is taken |
| The readiness data is mistaken for a real survey | Every page of this report states that the fleet is synthetic; the live inventory script exists to produce real data on real machines |

## 8. What we are asking for

| # | Decision | Owner | Date required |
|---|---|---|---|
| 1 | Approve Option A and the replacement schedule | Managing Director + Finance Director | This meeting |
| 2 | Approve the replacement budget for 31 devices (31 × the quoted device cost) | Finance Director | This meeting |
| 3 | Agree the department order for replacement (Finance, Management, then Operations, then Sales) | Department heads | This week |

> **Approval (unsigned until a review actually happens):**
> Managing Director: ................................................  Date: ................
> Finance Director: .................................................  Date: ................

> **Lab note:** Halden Distribution Ltd. is fictional and this report is a home-lab portfolio artefact.
> The fleet counts and percentages labelled "synthetic fleet" come from an invented dataset produced by
> a deterministic generator; they are reproducible by re-running the generator, and they are not a
> measurement of real hardware. All other content — the requirements, the method and the runbooks —
> reflects work that is real and executable.
