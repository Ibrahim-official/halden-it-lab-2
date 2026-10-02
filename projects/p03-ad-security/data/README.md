# Synthetic input data — P3 privileged access

**Everything in this folder is synthetic.** The people are invented for the fictional company
Halden Distribution Ltd. They are not real customers, colleagues or personal data, and no real
personal information is used anywhere in this project (AGENTS.md rules R2/R3/R6 and Section 4.6).

Label this data as **synthetic** anywhere it appears: in the register, in a diagram, in a report or
on the website.

| File | What it is |
|---|---|
| `halden-account-inventory.csv` | The planned account inventory used to plan admin tiering: one row per account (`Standard` daily-use accounts, and separate `adm-t{tier}-first.last` `Admin` accounts for IT roles that need one), with the tier each account is proposed for and the reason (`Basis`). Generated, not hand-written. |
| `gen_account_inventory.py` | The generator. It **references** the P1 synthetic staff file at `../../p01-core-infrastructure/data/halden-staff.csv` (the single source of truth for Halden's staff) and does not duplicate or copy it. Run `python3 gen_account_inventory.py` to regenerate. |

## How the inventory is derived

The generator reads the synthetic staff CSV and, for each person, writes:

1. a **Standard** row — the daily-use account, which never holds administrative rights, and
2. an **Admin** row — only for IT roles that genuinely need one, named
   `adm-t{tier}-first.last`, where the tier comes from the role:

| Halden role | Admin tier | Why that tier |
|---|---|---|
| IT Manager | Tier 0 | Owns the domain, the domain controllers and the directory itself (including P2's Entra connect work) |
| Systems Administrator | Tier 1 | Administers member servers and the applications running on them |
| IT Support Officer | Tier 2 | Administers workstations and user objects — password resets and unlocks by delegation |

Roles that must never hold an admin account (for example HR Officer and Recruiter) receive no
Admin row, and that absence is deliberate: it is the least-privilege decision, recorded in the
generator so it can be reviewed rather than assumed.

## What this inventory is not

- It is **not** a measurement. It describes what the lab *is designed to contain*. `CurrentTier` is
  deliberately `unassigned` and stays that way until the accounts exist in the lab and somebody has
  reviewed them.
- It is **not** an authentication source. No password, hash or credential appears in it — accounts
  are created by `scripts/07-Set-AdminTiering.ps1`, and any initial password goes to the git-ignored
  log under `projects/p03-ad-security/logs/`, then into the owner's password manager.
