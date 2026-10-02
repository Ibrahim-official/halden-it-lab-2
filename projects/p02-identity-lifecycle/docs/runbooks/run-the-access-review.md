# Runbook — Run the quarterly access review

**Applies to:** DC01 (export) and the department heads (sign-off) · **Frequency:** quarterly
**Owner:** IT Support (co-ordinates), department heads (decide)

> Why the business signs off, not IT: "who should keep access to Finance data?" is a business
> question. IT can produce the list and process the changes, but only the department head can say
> whether a person still needs the access. This runbook makes that a scheduled, evidenced process
> rather than an email that gets ignored.

## 1. Produce the review pack (IT)

```powershell
.\scripts\10-Export-AccessReview.ps1
```

The script writes, for each department, a review sheet containing for every user: user → groups →
resources the groups reach → last logon → manager, with a **Keep / Remove / Change** column filled in
by the reviewer. Output goes to `reports/access-review-<date>/`.

## 2. Send it to the department heads

Send each head **only their own department's sheet**, with a short covering note:

- what the review is and why it happens (least privilege, and the SysAdmin/audit checklist),
- the date it must come back by (suggest 10 working days),
- the rule: anything not explicitly marked **Keep** is treated as **Remove**,
- who to ask if a line looks wrong (IT, not the person named on the line).

## 3. Reviewers mark the sheet

For each user the head marks **Keep**, **Remove** or **Change** (with a note of what to change to).
The default is Keep; only exceptions need to be marked, but the sheet is not returned blank.

## 4. Process the agreed removals (IT)

Process **Remove** decisions through the normal change path — never by editing AD by hand:

1. Raise one change ticket for the review's removals.
2. Remove the group memberships through the mover path (update the HR export or run the targeted
   change), so the removal is logged like any other.
3. Re-run the access export and confirm the reviewed access is gone — this is the closure proof.

```powershell
.\scripts\10-Export-AccessReview.ps1 -Department 'Finance'
```

## 5. Track actions to closure

Every `Remove` or `Change` goes into the action tracker in
`business/p2-access-review-pack.md` with an owner, a due date, a status and a link to the evidence.
"Follow up on action items" is part of the job, so the tracker is a deliverable, not an afterthought.
Weekly, chase anything past its due date.

## 6. Sign-off

Each head returns a dated approval for their department. In this lab the sign-off is **role-played**
by the owner (there is no real Finance Director) and is recorded honestly as a simulation — the review
workflow, the export and the removals are real; the signature is a lab stand-in. The sign-off block
stays visibly unsigned until the review actually happens.

## Verification

- A review sheet exists for each department, with the decisions marked.
- Every removal has a change ticket and an audit-log line.
- The re-export after processing shows the removals gone.
- The action tracker shows every item closed, with evidence links.

## Rollback

Removals from a review are group-membership changes and are reversible: re-add the groups from the
"before" column of the audit log, and correct the reason in the tracker. If a head later reverses a
decision, it becomes a new access request with their fresh approval — not a silent re-add.
