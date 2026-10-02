# Halden Distribution Ltd. — Incident response tabletop exercise pack

**Exercise:** "Friday 16:30 — the files are renamed"
**Duration:** 60 minutes · **Facilitator:** IT (Muhammad Ibrahim Akmal)
**Participants:** Managing Director, Finance lead, HR lead, IT, and (role-played) external MSP
**Status:** **not yet run** — this is the facilitation pack and the report template. The outcome
section of `p07-tabletop-report.md` stays empty until the exercise has actually happened.

> Why a tabletop, and why run it before a real incident: an IR plan nobody has rehearsed is a
> document, not a capability. The tabletop is where the plan meets real people and real pressure, and
> where the gaps show up cheaply instead of expensively.

---

## 1. Objectives

1. Test whether management can make decisions with incomplete information under time pressure.
2. Test whether the escalation and communication routes actually work with real names.
3. Find gaps in the plan, the backups and the communications.
4. Produce tracked improvement actions with owners and dates (fed into P10).

## 2. Ground rules (read to participants first)

- It is a **discussion**, not a role-play performance. Nobody is being tested.
- No blame. If the plan is wrong, that is the exercise working correctly.
- Stay in the scenario; the facilitator will inject new information every ~10 minutes.
- There is no "right answer" to memorise; there is a documented decision to make.

## 3. Scenario (as presented to participants)

> **Friday 16:30.** The Finance team reports that files on the shared drive have been renamed with a
> `.locked` extension and a `README_RESTORE.txt` file has appeared. The file server is very slow. The
> helpdesk has three more calls in five minutes. Nothing on the status page has changed yet.

The scenario is delivered in injects so the information arrives the way it does in reality —
piecemeal and late.

## 4. Injects (every ~10 minutes)

| # | Time | Inject | Intended pressure |
|---|---|---|---|
| 1 | 0:00 | The opening scenario: `.locked` files, slow file server, helpdesk calls | Establish facts under pressure |
| 2 | 0:10 | The backup repository also appears to be affected; the last backup failed | Attackers target backups — does the plan cope with losing both? |
| 3 | 0:20 | A journalist emails asking for comment | External communication pressure |
| 4 | 0:30 | The CEO asks: "Should we just pay?" | The hardest management decision, made on incomplete facts |
| 5 | 0:40 | HR realises payroll data may be affected | Data-protection and notification decision |
| 6 | 0:50 | A staff member asks "are you watching my screen?" | The privacy question, live |
| 7 | 0:55 | IT finds the likely entry point: a phishing email opened two days earlier | Timeline and "could we have caught it earlier?" |

## 5. Questions the facilitator asks at each stage

- **Detect:** how would we have known about this at 02:00 instead of 16:30? What detection would
  need to fire?
- **Declare:** who declares this an incident, and what severity is it right now?
- **Roles:** who is the Incident Lead right now, and are they free to do the job?
- **Contain:** what do we do in the first 30 minutes? What could make it worse?
- **Decide:** who decides whether we pay, disclose or notify? What do they need to decide?
- **Communicate:** what do we tell staff, and when? The journalist — who answers?
- **Recover:** which backup do we restore from, and how do we know it is clean?
- **Privacy:** what is our honest answer to the staff member's question?
- **Learn:** one change that would make the next incident smaller.

## 6. Facilitator notes

- **Keep it moving.** If a debate runs long, note the open question and move on; the report captures
  it.
- **Push on the backup inject.** The plan is only credible if it survives losing the primary and the
  backup at once.
- **Do not let IT dominate.** The point is to test whether the **business** can decide, not only
  whether IT can work the keyboard.
- **Capture verbatim quotes** where they are revealing (for example an action that nobody owns).
- **Time everything.** Note the timestamp of each decision, because response time is a finding.

## 7. Artefacts the exercise produces

| Artefact | Owner | Where it goes |
|---|---|---|
| Tabletop report with findings and actions | Facilitator | `p07-tabletop-report.md` (outcomes filled after the run) |
| Improvement actions with owners and dates | Facilitator | P10 action tracker |
| Playbook/plan updates | IT | `../docs/runbooks/`, this pack, the IR plan |
| A "what we will do differently next time" summary for management | IT | Executive brief follow-up |

## 8. What "good" looks like

- The severity was declared out loud within the first 10 minutes.
- Everyone knew who the Incident Lead was by name.
- Communication happened on a schedule, not when someone remembered.
- The backup question produced a concrete answer, not a hope.
- At least three improvement actions came out with named owners.

> Halden Distribution Ltd. is a fictional company for a home-lab portfolio project. The exercise pack
> is real preparation; the participants, company and scenario are simulated.
