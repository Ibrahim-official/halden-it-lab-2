# Halden Distribution Ltd. — "State of IT" talk (10 minutes)

**Audience:** management and department heads · **Speaker:** IT Lead · **Date:** 2026-10-02
**Format:** 12 slides, one message each · **Recording length target:** 10 minutes
**Recording tool:** OBS Studio (screen and voice); stored privately, linked from the portfolio

> Halden Distribution Ltd. is a **fictional** 85-user company used for a home-lab portfolio. This is a
> **speaker-notes outline**. Every slide that would carry a number marks it as a placeholder to be
> filled from real measurements — no figure is written here. Where the number is not measured yet, the
> slide says so out loud rather than guessing. The recorded talk is an optional nice-to-have for P10
> (`AGENTS.md` Section 5.7).

## Talk structure and timing

| # | Slide | Message | Time |
|---|---|---|---|
| 1 | Where we started | The inherited state, in business terms | 45 s |
| 2 | What we did | P1–P9 on one timeline | 60 s |
| 3 | CIS IG1 | Before → after | 60 s |
| 4 | Identity | Access is controlled and revoked | 45 s |
| 5 | Resilience | "We can recover the business" | 45 s |
| 6 | Security | Attack paths and exposure | 45 s |
| 7 | Service | The desk and what it fixes | 45 s |
| 8 | Top 5 remaining risks | From the register | 60 s |
| 9 | 90-day roadmap | What we propose to do next | 60 s |
| 10 | Budget asks | Cost, risk reduced, option to defer | 60 s |
| 11 | Decisions needed today | The ask | 45 s |
| 12 | Appendix | KPI definitions | — |

---

## Slide 1 — Where we started

**On the slide:** a simple before/after of the inherited state: one server, everyone an administrator,
no MFA, backups never tested, assets on a spreadsheet.

**Speaker notes:** "Twelve months ago Halden ran on one server with no spare. If it failed, nobody
could log in, get an address or open a file. Every one of the 85 staff had full control of the shared
drive, so one mistake or one virus could destroy any department's data. There was no MFA, the backups
had never been restored, and nobody could tell you who could read Finance data."

## Slide 2 — What we did

**On the slide:** a 90-day timeline. Nine projects as milestones: foundation, identity, security,
endpoints, patching, network, monitoring, resilience, service desk. Plus this governance layer.

**Speaker notes:** "We rebuilt the foundation, then wrapped identity, security, patching, the network,
monitoring, backup and a service desk around it — nine pieces of work, each with its own documentation
and its own measured result. This talk is about the tenth and last piece: the governance and reporting
that makes all of it accountable."

## Slide 3 — CIS IG1: before → after

**On the slide:** the before/after bar chart. **This slide carries placeholders today.** The chart in
the repository (`docs/diagrams/p10-cis-ig1-chart-template.svg`) is a labelled **empty** template; the
bars are filled only from real, evidenced scores.

**Speaker notes:** "We measure ourselves against the CIS Controls Implementation Group 1 — 56
safeguards that industry and our insurers treat as the minimum standard for a business our size. Here
is where we started and where we are. I want to be straight with you: a safeguard only counts as
'fully implemented' when there is evidence for it — the tool we use literally refuses the score
otherwise. So this is an honest number, not a marketing one. The chart fills in as each project's
evidence is produced."

## Slide 4 — Identity: access is controlled, and revoked

**On the slide:** joiner/mover/leaver flow diagram; MFA status. Values shown as placeholders to be
replaced with the P2 measurements.

**Speaker notes:** "Access used to be granted by whoever answered the phone, and removed... eventually.
Now every account is created from the HR record, changes with the person's role, and is disabled the
moment they leave. Multi-factor authentication protects remote and administrative access. The numbers
on this slide come from the identity project's own reports."

## Slide 5 — Resilience: we can recover the business

**On the slide:** the backup data flow (three copies, two media, one off-site, one immutable) and the
restore-test result. RTO/RPO shown as targets until a drill measures them.

**Speaker notes:** "We no longer ask you to trust that the backups work — we test them. A copy is kept
off-site and immutable, so ransomware cannot reach it, and the backup server is deliberately not part
of the domain. The recovery times you see are **targets** agreed with you; the measured figure appears
here only after a timed drill has actually run."

## Slide 6 — Security: fewer ways in, and we would see it

**On the slide:** attack paths to administrator, known-exploited exposure, and detection coverage.
Placeholders to be filled from P3/P5/P7.

**Speaker notes:** "We mapped the ways an attacker could reach the keys to the domain and closed them,
we hardened the servers and endpoints, and we now collect and alert on security events across the
estate. The point is not a single number — it is that the number exists, is checked, and moves in the
right direction."

## Slide 7 — Service: the desk and what it fixes

**On the slide:** ticket volumes, SLA compliance, the top recurring issues. Placeholders until the
service desk has real data.

**Speaker notes:** "Every request, problem and change now goes through one place with a service
level and a person accountable. That gives us two things: staff get a predictable response, and we get
data on what actually breaks, so we fix causes instead of symptoms."

## Slide 8 — Top 5 remaining risks

**On the slide:** the five highest-rated risks from the register, each with a **business** owner and a
recommended decision. The register is **empty today**, so this slide shows the methodology and will
name the risks once the CIS IG1 assessment populates it.

**Speaker notes:** "These are the five things I would lose sleep over, in business terms — what could
happen, how likely it is, and who in this room owns it. I am asking each owner to either accept the
risk knowingly, mitigate it, or defer it with the consequence understood. The largest expected gap is
security awareness: our biggest realistic threat is a phishing email that someone clicks."

## Slide 9 — 90-day roadmap

**On the slide:** five costed workstreams with the risk each reduces.

**Speaker notes (the proposed items):**
1. **Security awareness training and a phishing simulation** — closes the eight Control 14 safeguards.
2. **Replacement of the remaining unsupported Windows 10 devices** — closes the largest remaining
   endpoint exposure.
3. **A real off-site backup subscription** — removes the single-site dependency.
4. **An Intune/Autopilot evaluation** — makes new devices consistent and manageable at scale.
5. **A second firewall for high availability** — removes a network single point of failure.

Each is costed with three figures: the cost, the risk it reduces, and what happens if we defer it.

## Slide 10 — Budget asks

**On the slide:** a table of the five items above with cost, risk reduced and option to defer.

**Speaker notes:** "I am not asking you to fund all of this today. I am asking you to decide *with* me:
each line has a cost, a risk it removes and a consequence if we wait. The awareness training is the
cheapest and reduces the biggest human risk, so I would start there."

## Slide 11 — Decisions needed today

**On the slide:** three decisions.

**Speaker notes:** "Three things: approve the IT policy pack; nominate a **business** owner for each
risk on the register; and tell me whether the 90-day roadmap is funded or deferred. Everything else I
can carry."

## Slide 12 — Appendix: KPI definitions

**On the slide:** one line per KPI, its formula and its target.

**Speaker notes:** "For reference: how each number you have seen is calculated, so you can hold me to
it. They are all defined in the governance project's `configs/kpi-definitions.csv`."

---

## Recording plan (OBS)

1. Rehearse to the timings above; the target is 10 minutes, hard limit 12.
2. Record screen and voice; keep the camera optional. Use a clean desktop with generous zoom (the
   charts and diagrams must be legible on a phone).
3. Speak the honest gap out loud — say "not measured yet" where that is true. Interviewers respond
   well to a candidate who distinguishes measurement from assertion.
4. Save the file privately; link it from the portfolio only after the owner has reviewed it
   (`AGENTS.md` R6: publishing needs an explicit go-ahead).

## What this talk proves (interview framing)

- **"How would you report IT to non-technical management?"** This is the answer: business objectives →
  KPIs → RAG status → the risks that need a decision, ending in a clear ask.
- **"Tell me about a process you improved."** Change management: the before (Friday-afternoon
  changes), the after (classified, risk-assessed, rollback-required, CAB-approved), and the measured
  effect (emergency-change share, success rate).
- **"How do you prioritise with limited budget?"** CIS IG1 as the baseline, the risk register for
  scoring, and a costed roadmap that lets management choose — with the deferral consequence stated.
