# Synthetic input data — P2 identity lifecycle

**Everything in this folder is synthetic.** These are invented people and account names for the
fictional company Halden Distribution Ltd. They are **not** real customers, colleagues or personal
data, and no real personal information is used anywhere in this project (AGENTS.md rules R2/R3/R6
and Section 4.6).

The 85-person staff list itself lives **once**, in the P1 dataset
(`projects/p01-core-infrastructure/data/halden-staff.csv`). P2 does not duplicate it: this folder
holds only what P2 needs *on top of* that file, and the full HR export is **generated** from it.

| File | What it is |
|---|---|
| `hr-export-sample.csv` | A small demonstration subset in the P2 HR-export shape (`EmployeeID,First,Last,Department,Title,ManagerID,Status,StartDate,EndDate,Office`). It shows all three lifecycle paths against P1 identities: **Mover** — 1007 Laiba Qureshi moved from Finance/Accountant to Operations/Dispatcher; **Leaver** — 1042 Mahnoor Malik; **Joiner** — 1086 Nadia Sheikh, a new starter. The remaining rows are unchanged people so a dry run has something to skip. |
| `hr-export-corrupt-sample.csv` | A deliberately corrupted fixture for the **circuit-breaker** test: every status is wrongly set to `Leaver`, so a run without a circuit breaker would disable most of the company. It must never be copied over `hr-export.csv`. |
| `protected-accounts.txt` | Accounts the engine must never disable or modify (service identities, the cloud break-glass accounts, built-in and server accounts). |
| `entitlements-export-sample.csv` | An illustrative sample of the access-review export **shape** only. `LastLogonDate` is empty because it is a real value the script reads from AD; `ReviewDecision` is empty because a department head fills it in. |
| `gen_hr_export.py` | The generator that derives `hr-export.csv` from the P1 staff file, adding `ManagerID`, `Status` and `EndDate`. This is why the full export is not committed as a second copy of the 85 people. |

## Generating the full HR export

```bash
python3 gen_hr_export.py                 # writes hr-export.csv beside this script
python3 gen_hr_export.py --dry-run       # report only
python3 gen_hr_export.py --mark-leaver 1042 --end-date 2026-10-02
```

`hr-export.csv` is a generated artifact. Treat the P1 staff file as the source of the people and this
generator as the source of the lifecycle columns; do not hand-edit the generated file.

## Why P2 adds `ManagerID` and `Status`

- **`ManagerID`** — the staff file stores a manager as a name (`iqra.zafar`). A name is not a safe
  key, so the export resolves it to the manager's `EmployeeID` and the engine sets the AD `Manager`
  attribute from the number, never from a name.
- **`Status` and `EndDate`** — the lifecycle trigger. `Active` plus a start date drives the joiner
  path; `Leaver` with an end date drives the leaver path. This is the one column HR must maintain
  correctly, because everything else is derived from it.

**Labelling requirement:** anywhere this data appears in a report, screenshot or website page it must
be marked "synthetic". The 85-user HR file is not evidence of a real organisation.
