# Halden Distribution Ltd. — file share permission matrix

**Purpose:** the single document that says who can read and who can change which shared folder.
**Owner:** IT (Muhammad Ibrahim Akmal) · **Approvers:** department heads (access is a business
decision, not an IT decision) · **Review:** quarterly, plus on every joiner/mover/leaver (P2)

**How to read it:** `RW` = read and change · `RO` = read only · `—` = no access, and the folder is
not even visible (Access-Based Enumeration is on). Every right is granted through a **domain local
group** (`DL_…`); no individual user is ever named on a folder. To add someone, add them to the
right role group (`G_…`) — the folder permission follows automatically.

| Share (drive letter) | Finance | HR | Sales | Operations | Management | IT | Everyone else |
|---|---|---|---|---|---|---|---|
| **Finance** (F:) — `DL_Share-Finance_RW` / `_RO` | RW | — | — | — | RO | RO | — |
| **HR** (H:) — `DL_Share-HR_RW` / `_RO` | — | RW | — | — | RO | RO | — |
| **Sales** (S:) — `DL_Share-Sales_RW` | — | — | RW | — | RO | RO | — |
| **Operations** (O:) — `DL_Share-Operations_RW` | — | — | — | RW | RO | RO | — |
| **Company** (G:) — `DL_Share-Company_RO` | RO | RO | RO | RO | RO | RO | RO (all staff) |
| **Users$** (home drive) — `DL_Share-Users_Home` | own folder only (full control inside it) | | | | | | — |

Notes:

- **IT** holds read access for support; IT does not hold write access to departmental content by
  design. Write access to a business folder is granted only by adding the person to that
  department's `G_` role group.
- **Management** holds read-only access across departments so directors can review, but cannot
  change departmental content.
- **Administrators** retain full control at the file-server level for recovery; this is not used
  for day-to-day access and is recorded here deliberately rather than left implicit.
- Every folder is protected by **FSRM file screens** that block executable files, and by
  **twice-daily shadow copies** for self-service restores.

## Approval

Access is approved by the business, not by IT. Please complete the table below for your
department and return it to IT; unapproved rows are removed at the quarterly review.

| Department | Approver name | Role | Date | Signature / approval |
|---|---|---|---|---|
| Finance |  | Finance Director |  |  |
| HR |  | HR Director |  |  |
| Sales |  | Sales Director |  |  |
| Operations / Warehouse |  | Operations Director |  |  |
| Management |  | Managing Director |  |  |
| IT |  | IT |  |  |

> **Status:** designed and enforced in the lab; **the signature column is unsigned** until the
> department-head review actually happens (see `PROGRESS.md`). It is deliberately left blank rather
> than pre-filled.
