# Joiner–Mover–Leaver process and RACI — Halden Distribution Ltd.

**Owner:** IT (Muhammad Ibrahim Akmal) · **Approvers:** HR Director and department heads
**For:** HR, line managers, department heads and IT · **Version:** 1.0 (2026-10-02)

> **Read this if you are not technical.** This document says who does what when somebody joins the
> company, changes role, or leaves. You do not need to know anything about servers to use it: your
> part is to keep one record accurate and to approve access. IT's part is automated.

---

## 1. Why this exists

Most access problems at a company this size are not caused by a server fault. They are caused by a
message that was never sent, or a change that was never made:

- a new starter waits for access because IT was not told in time;
- someone changes department and keeps the old department's access for years;
- a leaver's account stays open because nobody remembered to raise it.

The fix is a process where *one record* — the HR file — is the trigger for everything, and IT's
automation reconciles the accounts to it. Nobody has to remember to email anybody.

## 2. Who is accountable (RACI)

**R** = does the work · **A** = accountable for the outcome · **C** = consulted · **I** = informed.

| Step | HR | Line manager | Department head | IT |
|---|---|---|---|---|
| Record the joiner / mover / leaver in the HR system | **R/A** | C | I | I |
| Approve access for the new or changed role | I | C | **R/A** | C |
| Keep the role matrix up to date | C | I | **R/A** | R (maintains the file) |
| Build, change or remove the account and its access | I | I | I | **R/A** |
| Hand the first credential to the new starter | I | **R/A** | I | C (provides it securely) |
| Collect equipment from a leaver | I | **R/A** | I | C |
| Confirm the leaver's access is gone | I | I | I | **R/A** |
| Quarterly access review and sign-off | C | I | **R/A** | R (produces the pack) |
| Keep the audit record of every change | I | I | I | **R/A** |

The pattern is deliberate: **the business decides who should have access; IT proves what happened.**

## 3. The joiner process

| # | Who | What | Target |
|---|---|---|---|
| 1 | HR | Adds the new starter to the HR system: name, start date, department, job title, manager, employee number | As soon as the hire is confirmed |
| 2 | Department head | Confirms the access the role needs (a standard role needs nothing extra) | Before the start date |
| 3 | IT | Reviews the automated plan for this person (a preview, which changes nothing) | Day −5 |
| 4 | IT | Applies it: account, role groups, home drive, licence | Day −3 to day −1 |
| 5 | IT → line manager | Provides the first credential, or a temporary pass for cloud sign-in, through the agreed secure channel (**never** clear-text email) | Day −1 |
| 6 | New starter → line manager | Signs in, sets their own password, enrols the authenticator app | Day 1 |
| 7 | IT | Confirms the account, groups and folder are correct and closes the ticket | Day 1 |

**Target:** the starter's first morning should be spent working, not waiting.

## 4. The mover process (changing role)

| # | Who | What |
|---|---|---|
| 1 | HR | Updates the person's department and/or job title in the HR system — nothing else |
| 2 | Receiving department head | Approves the access the new role needs; the previous head is told the old access is ending |
| 3 | IT | Runs the automated change, which **removes the old role's access and adds the new role's access in the same pass** |
| 4 | IT | Asks the person to sign out and back in, then confirms they can open the new department's folder **and can no longer open the old one** |
| 5 | IT | Records what was added and what was removed on the ticket |

The one rule that matters: **the old access goes at the same time as the new access arrives.** This is
what stops access building up over a career.

## 5. The leaver process

### What HR does (the whole of your part)

1. Set the person's **Status** to `Leaver`.
2. Set **EndDate** to the last working day.
3. If the person must be cut off **immediately** (a dismissal or a security concern), say so in the
   comment **and telephone the IT Service Desk** — there is a separate urgent path.

That is it. You do not need to tell anybody else, and you do not need to do anything technical.

### What happens automatically after that

4. IT's automation records the access the person currently has (needed for investigations and
   rehires), disables the account, removes them from every group, and moves the account to the
   disabled area of the directory. **Target: within 15 minutes of the HR record changing.**
5. IT confirms it is done, with a dated line in the audit record.
6. The account is **kept, disabled, for 90 days** — not deleted — in case of a payroll query, a legal
   hold or a rehire. Deletion happens later, after a report and a check.

### What the line manager does

- Collect the laptop, phone, pass and keys, and return the equipment to IT.
- Tell IT about anything only that person could do, so the access or knowledge can be reassigned
  deliberately instead of being lost by accident.
- **Do not** ask IT to "leave their access on for a bit, just in case". If continuing access is
  genuinely needed, that is a new, time-limited approval from the department head, recorded like any
  other access change.

## 6. The agreement between HR and IT (SLA)

| Event | Target | How it is evidenced |
|---|---|---|
| Joiner ready for work | Before day 1 (account built by day −1) | The audit record shows the account was created before the start date |
| Mover access changed | Same day as the HR change | The audit record shows the group removals and additions |
| Leaver access removed | Within 15 minutes of the HR record change; immediate for the urgent path | The audit record timestamp for the leaver |
| Quarterly access review | Pack issued to heads, decisions back within 10 working days | The dated review pack and the sign-off sheet |
| Stale account review | Monthly report; every unexplained account resolved | The hygiene report and the action tracker |

**One dependency sits with HR:** if `Status` is not kept up to date, the leaver timer does not start.
That is the single point of failure in this whole process, and it is why the leaver runbook is
written for a non-technical reader.

## 7. What changes for staff

- **Nothing on day one** for most people: access arrives automatically.
- **If a drive or folder is missing**, sign out and back in once. If it is still missing, raise a
  ticket — do not try to map it by hand.
- **You will be asked to set up an authenticator app** on your phone when MFA is rolled out. There is
  a one-page guide and a helpdesk surge plan; nobody will be locked out without a route back in.
- **If you believe you have access you should not have**, tell IT. Removed access is a positive
  outcome of the quarterly review, not a punishment.

> **Lab note:** Halden Distribution Ltd. is a **fictional company** in a home-lab portfolio project.
> The 85-person staff file is **synthetic** (invented names, no real personal data). This process
> document is written as if for a real organisation, and the sign-off below is deliberately left
> blank: it is completed when a real review happens, not pre-filled.

## 8. Approvals

| Department | Approver name | Role | Date | Signature / approval |
|---|---|---|---|---|
| HR |  | HR Director |  |  |
| Finance |  | Finance Director |  |  |
| Sales |  | Sales Director |  |  |
| Operations / Warehouse |  | Operations Director |  |  |
| Management |  | Managing Director |  |  |
| IT |  | IT Manager |  |  |

**Status: unsigned.** The process is documented and enforced in the lab; the signature column stays
empty until the process review actually happens.
