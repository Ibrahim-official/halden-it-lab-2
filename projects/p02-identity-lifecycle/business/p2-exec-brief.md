# Halden Distribution Ltd. — Executive brief: identity lifecycle and access governance

**For:** Managing Director, Finance Director, HR Director and department heads
**From:** IT (Muhammad Ibrahim Akmal) · **Date:** 2026-10-02 · **Change record:** `p02-change-record.md`
**One-line summary:** stop access being granted by memory and removed by luck.

---

## The issue in one paragraph

Today, HR emails IT when someone joins, moves or leaves — sometimes. New starters wait days for the
access they need, people who change department keep their old permissions, leavers' accounts stay
open until someone remembers, and there is no second factor on any account. When the Finance
Director asks "who can see payroll?", the honest answer is "we would have to check". That is a
business risk, not an IT detail: stolen logins are the single most common way a company is breached,
and offboarding gaps are one of the most frequent findings in access audits.

## What we are changing

| Today | After this change |
|---|---|
| Access is requested by email and built by hand | Access is built automatically from the HR record and a role matrix the departments approve |
| A new starter waits for IT | The account, groups, home drive and licence are ready before day one |
| A person who changes role keeps the old role's access | The old access is removed and the new access added in the same automated run |
| A leaver's account stays open until someone remembers | A leaver is disabled, stripped of access and recorded within 15 minutes of HR recording them |
| A password is enough to sign in | MFA is required for everyone; old-style protocols are blocked |
| Nobody can list who has access to what | A quarterly review pack is produced per department, and each head signs off the removals |

## What it costs and what it needs from the business

**Cost:** nothing. The work uses the tools already licensed for the lab trial and free open-source
tools. **Time:** about two weeks, phased.

**What we need from you:**

1. **The department heads to approve the role matrix** (`p2-role-matrix.md`) — this is the list that
   says which job title gets which access. IT implements it; the business owns it.
2. **HR to keep one column accurate** — the employee's `Status` (Active or Leaver) and their end
   date. Everything else flows from that.
3. **HR and line managers to follow the one-page leaver process** (`p2-jml-process-and-raci.md`),
   which is written so a non-technical reader can do it.
4. **The department heads to spend about 30 minutes a quarter** on the access review.

## The controls that make this safe

- **Nothing changes without a preview.** The automation can be run in a mode that shows exactly what
  it would do and changes nothing.
- **A safety cut-out.** If a bad HR file would disable a large share of accounts in one go, the
  process stops and asks a human instead of doing it.
- **A complete record.** Every account change is written to a log with the before and after values,
  so "what did this person have access to on the day they left?" is answerable months later.
- **No privileged automation.** The process runs with rights over two folders' worth of the
  directory only, not as a domain administrator.

## How we will report on it

The KPI report (`p2-kpi.md`) tracks five numbers: joiner lead time, leaver revocation time, MFA
coverage, stale accounts, and the share of baseline security checks passing before and after. Each
one is filled from a real measurement once the change is live — the template deliberately shows
"not measured yet" until then.

## What this does not fix

It does not make the company unhackable, and it does not cover backups (a later project does that).
It closes the specific gap that "nobody can say who has access, or prove it was removed".

> **Lab note:** Halden Distribution Ltd. is a **fictional company** used for a home-lab portfolio
> project. The 85-person staff file is **synthetic** (invented names, no real personal data). The
> configurations, scripts and tests are real; the business approvals below are recorded honestly as
> simulations of a real process, not as real sign-offs.

## Approval

| Role | Name | Decision | Date |
|---|---|---|---|
| Managing Director |  |  |  |
| Finance Director |  |  |  |
| HR Director |  |  |  |
| IT | Muhammad Ibrahim Akmal (role-played owner) |  |  |

*The signature block is deliberately left unsigned. It is completed when the change is actually
approved, not pre-filled for appearance.*
