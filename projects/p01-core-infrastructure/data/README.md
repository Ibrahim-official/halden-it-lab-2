# Synthetic input data

**Everything in this folder is synthetic.** These are invented people for the fictional company
Halden Distribution Ltd. They are **not** real customers, colleagues or personal data, and no real
personal information is used anywhere in this project (AGENTS.md rule R3/R6 and Section 4.6).

| File | What it is |
|---|---|
| `halden-staff.csv` | The HR "source of truth" export: 85 invented staff (`First,Last,Department,Title,Manager,Office,EmployeeID,StartDate`) across Management, Finance, HR, Sales, Operations and IT. This is the input to `../scripts/04-Import-HaldenUsers.ps1` and later to the P2 joiner-mover-leaver engine. |
| `gen_staff.py` | The small generator that produced the CSV, so the dataset is reproducible and its randomness is verifiable rather than hand-faked. Run `python3 gen_staff.py > halden-staff.csv` to regenerate. |

**Labelling requirement:** anywhere this data appears in a report, screenshot or website page it
must be marked "synthetic" — the synthetic 85-user HR file is not evidence of a real organisation.
