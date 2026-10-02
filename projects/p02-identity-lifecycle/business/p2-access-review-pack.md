# Access review pack — quarterly review, with sign-off and action tracker

**Owner:** IT (Muhammad Ibrahim Akmal) · **Approvers:** department heads · **Cycle:** quarterly
**Produced by:** `scripts/10-Export-AccessReview.ps1` (one sheet per department)
**Process:** `docs/runbooks/run-the-access-review.md`

> **Status: the review has not been run yet.** The sheet below is the template the process fills in.
> Nothing in it is a measured result: the "Last logon" column is empty because it is a real value the
> script reads from the directory, and the decision column is empty because a department head fills it
> in. When the review runs, the real export is attached and this template is replaced with it.

---

## 1. What the reviewer is being asked to do

For each person in your department, mark one of:

- **Keep** — this person still needs this access for their current job.
- **Remove** — they no longer need it. IT will remove it and record the change.
- **Change** — they need something different; write what in the note.

The default is Keep. Anything you do not mark is treated as **Keep** — the review is a positive
confirmation that the access is still needed, not a trap. The one rule that does matter: **if you
know someone no longer needs an access, say Remove.** That is the entire point of the exercise.

## 2. Review sheet

**Department:** ________________ · **Reviewer (department head):** ________________ · **Date:** ________

| Employee ID | User | Current role groups | Reaches (resources) | Last logon | Decision | Note |
|---|---|---|---|---|---|---|
|  |  |  |  |  | ☐ Keep ☐ Remove ☐ Change |  |
|  |  |  |  |  | ☐ Keep ☐ Remove ☐ Change |  |
|  |  |  |  |  | ☐ Keep ☐ Remove ☐ Change |  |
|  |  |  |  |  | ☐ Keep ☐ Remove ☐ Change |  |
|  |  |  |  |  | ☐ Keep ☐ Remove ☐ Change |  |

*(The live sheet is generated per department by the script and contains every user in the
department; the five rows above show the shape only.)*

## 3. Sign-off

By signing, the department head confirms they have reviewed the access for their department, that
each listed access is still required for that person's current role, and that the removals marked
above should be actioned.

| Field | Value |
|---|---|
| Department | ____________________ |
| Department head (name) | ____________________ |
| Date reviewed | ____________________ |
| Decisions: Keep / Remove / Change | ______ / ______ / ______ |
| Signature or written approval | ____________________ |

**This block is deliberately blank.** In this lab the sign-off is **role-played** by the project
owner, because there is no real Finance Director or HR Director: the review workflow, the export and
the removals are real, and the signature is honestly recorded as a simulation of the process rather
than a real approval.

## 4. Action tracker (the follow-up)

Every Remove or Change is an action. This table is where it is tracked to closure — "follow up on
action items" is part of the job, so the tracker is a deliverable, not an afterthought.

| # | Action | Department | Owner | Raised | Due | Status | Evidence link |
|---|---|---|---|---|---|---|---|
| 1 |  |  |  |  |  | Open |  |
| 2 |  |  |  |  |  | Open |  |
| 3 |  |  |  |  |  | Open |  |
| 4 |  |  |  |  |  | Open |  |
| 5 |  |  |  |  |  | Open |  |

**Status values:** Open · In progress · Blocked (with reason) · Closed (with evidence link). An action
is closed only when the change is applied **and** a re-export shows it is gone.

## 5. Review cycle

| Step | Owner | Expected |
|---|---|---|
| Pack generated and sent | IT | Day 0 |
| Decisions returned | Department head | within 10 working days |
| Removals processed through the change path | IT | within 5 working days of return |
| Re-export proving closure | IT | with the change ticket |
| Tracker fully closed | IT | before the next quarter's pack is issued |

## 6. What a good review looks like

- Every department returned a decision for every user.
- Every Remove has a ticket, an audit line, and a re-export showing the access gone.
- The tracker has no Open items when the next pack is issued.
- Nobody was removed from something they still needed — because the department head, not IT, made the
  decision.

> **Lab note:** Halden Distribution Ltd. is a **fictional company** and the staff data in the review
> sheets is **synthetic** (invented names, no real personal data). This pack is a real process applied
> to lab data; the sign-off is a role-play and is recorded as such.
