# Runbook — The recurring privileged-access review

**Applies to:** DC01 · **Time:** 30 minutes automated, plus a 30-minute human review ·
**When:** automated checks monthly; the full human review quarterly and after any privileged change

## Why

Privilege creep is not a mistake, it is the normal drift of an organisation: someone covers for a
colleague, a project grants temporary rights, a leaver is disabled but not removed from a group. A
tiering model applied once and never reviewed is a diagram, not a control. This review is the
control — and it is also a requirement in the System Administrator job ad ("perform regular security
checks and support remediation").

## 1. Run the automated part (read-only)

```bash
# From a management host inside the lab.
cd projects/p03-ad-security/scripts
./12-Invoke-PrivilegedAccessReview.sh --dry-run      # see what it will do
./12-Invoke-PrivilegedAccessReview.sh                # run it
```

It runs the two read-only checks on the target DC over PowerShell remoting and archives the output
under `evidence/raw/p03-privileged-access-reviews/<date>/`:

| Script | Answers |
|---|---|
| `10-Test-PrivilegedAccess.ps1` | Which privileged groups, flags, ACLs and delegations are exceptions right now? |
| `11-Verify-Remediation.ps1` | Which of the P3 controls is still actually in place? |

Read the results script by script — a PASS row only counts if it came from today's run.

## 2. Decide, per exception (the human part)

The script cannot make a judgement, so the reviewer does. For each exception:

| Question | Outcome |
|---|---|
| Is the access still needed for the person's role? | If yes → keep, and note why in the register |
| Is it needed temporarily (cover, project)? | If yes → keep with an **expiry date**, and diarise the removal |
| Is it no longer needed? | Remove it the same day and record the removal |
| Is it needed but risky (a business constraint)? | **Risk-accept** it: a named business owner, a written reason, and a review date |

A privileged account with no current role holder is a finding in itself: nobody is accountable for
it.

## 3. Verify the specific controls that decay quietly

| Control | Check |
|---|---|
| Domain Admins membership | Only `adm-t0-*` and the built-in Administrator remain |
| Protected Users | Human Tier 0 accounts only — never a service or computer account |
| Deny-logon rules | Still linked to the workstation, server and DC OUs, and still enforced by a live test |
| LAPS read access | The exact list of people who can read a password is still justified, tier by tier |
| Helpdesk delegation | Still limited to password reset and unlock on user OUs; nothing on Tier 0 objects |
| Legacy accounts | Disabled accounts and old service accounts are still disabled |
| Audit sources | NTLM (8004), Kerberos (4769) and LAPS (10018) events are still being produced |

## 4. Close the loop

- Update `business/p03-privileged-access-policy.md` in its review section with the date, the
  reviewer, the exceptions accepted and their review dates.
- Update the findings register statuses: a finding is only closed when the control has been verified,
  not when it was applied.
- When P10 exists, feed the review output into the monthly management report and the KPI dashboard,
  including how many exceptions were open, closed and risk-accepted.

## Rollback

Read-only. The only changes this runbook makes are ones the reviewer deliberately applies while
working through the exceptions, and each of those is reversible: re-add a group membership, or
re-create a delegation ACE with `07-Set-AdminTiering.ps1`.

> The review is a business process with an IT input, not an IT process with a business signature.
> The person who can explain *why* a right exists is the department head, and that is whose answer
> belongs in the register.
