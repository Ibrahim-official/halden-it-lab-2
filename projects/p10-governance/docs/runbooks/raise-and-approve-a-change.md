# Runbook — Raise and approve a change

**Applies to:** any change in Halden · **Time:** 15 minutes to raise; CAB weekly · **Owner:** IT Lead · **Runs:** on demand

Every change to a Halden service follows this path. It exists so that "what changed last week, and
who approved it?" can be answered in seconds, and so a risky change never happens by accident on a
Friday afternoon. The classification is in `configs/change-type-matrix.csv`.

## 1. Classify the change

| If the change… | Type | Approval |
|---|---|---|
| is routine, low-risk, repeatable and already documented in a procedure | **standard** | none per instance (the catalogue is approved once) |
| is anything else | **normal** | weekly CAB |
| is needed now to restore service or stop an active threat | **emergency** | ECAB by phone; retrospective within 2 business days |

If you are unsure, treat it as **normal**. That is the safe default.

## 2. Raise it (normal and emergency)

1. **Snapshot the affected VM(s) first** (AGENTS.md R4). Name the snapshot
   `snap-p10-<change-id>-before`. Every change needs a rollback, and the snapshot is usually it.
2. **Add a row to the register** `projects/p10-governance/data/change-log.csv`. Fill every required
   field; the ones that matter most are:
   - `title`, `change_type`, `risk` (low/medium/high), `requested_by`, `category`
   - `affected_services` — take this from the **P9 CMDB**, not from memory
   - `test_plan` — how you will know it worked
   - `rollback_plan` — how you will undo it. **A change with no rollback plan cannot be approved.**
   - `cab_reference` — the CAB this goes to
3. **Assess the risk.** Score likelihood × impact, then answer the checklist in
   `configs/change-policy-fields.yaml`: does it touch Tier 0? affect many users? tested? rollback
   tested? in a freeze period? does it change a CIS IG1 control? Any high-risk or Tier 0 change goes
   to management, not just the IT Lead.
4. **Validate the register:**
   ```bash
   cd projects/p10-governance
   python3 scripts/change_log.py --validate --open-errors
   ```
   Fix any error before sending it to the CAB.

## 3. Approve it at the CAB

1. **Generate the agenda** (the CAB chair does this before the meeting):
   ```bash
   python3 scripts/change_log.py --cab-agenda --out reports/cab-agenda-<date>.md
   ```
2. **Run the meeting** to the generated agenda: emergency retrospectives, changes awaiting approval,
   changes implemented, reviews due, risks and unauthorised changes, actions. Fifteen minutes.
3. **Record the decision** in two places: the minutes (`business/p10-cab-minutes.md` pattern) and the
   register — set `approver`, `approval_date` and `status: approved`. The script never writes an
   approval for you; that is deliberate.

## 4. Implement and close the loop

1. **Implement** in the agreed window, with the snapshot in place.
2. **Test** against the test plan and record the result.
3. **Post-implementation review (PIR):** fill `post_implementation_review` and set
   `status: reviewed`. For an **emergency** change this is not optional — it must happen within two
   business days, and the tool errors if it is missing.
4. **Close linked actions.** If the change fixed a finding, close the action in
   `data/action-tracker.csv` and note the change ID.

## 5. If you skipped this process

An unapproved change is detected by the **P9 config drift check** (a tracked config changed with no
matching approved change record). When that happens: raise a ticket, find the root cause, and add the
lesson to this procedure or to staff training. The unauthorised change is counted in the change KPI
so management can see it.

**Rollback:** the change's own `rollback_plan` — for most Halden changes that is reverting the
`snap-p10-<change-id>-before` snapshot and re-running the previous project's idempotent scripts. For a
domain controller, fix forward where possible: reverting a DC snapshot can disturb replication.
