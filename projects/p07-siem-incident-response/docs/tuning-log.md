# P7 tuning log

**Purpose:** every time a detection is quietened, the decision is written here — rule id, the narrow
exception, the reason and the date. Tuning is a documented decision, never a habit
(AGENTS.md 4.4 and the P7 plan Phase 4).

**Two rules that are not negotiable:**

1. **Never disable a rule to reduce noise.** Suppress a specific process + path + host instead.
2. **A tuning entry without a reason is not allowed.** If the reason cannot be written, the alert
   should be investigated rather than suppressed.

| Date | Rule id | Alert as seen | Root cause of the noise | Narrow exception applied | Verified afterwards | Analyst |
|---|---|---|---|---|---|---|
| *(empty — filled during Phase 4)* | | | | | | |

## How to add an entry (the method)

1. Run the environment through a few days of normal activity (scripted logons, file access,
   patching) and count alerts **by rule**.
2. For the loudest rules, look at the details. Is it a legitimate process, or is the rule too broad?
3. If it is a legitimate process, write the **narrowest** exception that still catches the behaviour:
   a specific image **and** path **and** host, never "exclude this event id".
4. Apply it, then re-run the scenario to confirm the rule still fires for the bad case.
5. Record the entry above with the reason and the verification.

## Before/after measures (filled from real runs only)

| Measure | Before tuning | After tuning |
|---|---|---|
| Alerts per day (all) | not measured | not measured |
| Alerts per day (High+) | not measured | not measured |
| Share of High+ that were true positives | not measured | not measured |

> These stay "not measured" until the lab run actually produces them. A tuning log with invented
> numbers would defeat its own purpose (AGENTS.md R2).
