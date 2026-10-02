# Management deck outline — P3 AD security assessment (5 slides)

**Audience:** Managing Director, department heads · **Duration:** 10 minutes plus questions
**Prepared by:** Muhammad Ibrahim Akmal, IT (Systems) · **Date:** 2026-10-02
**Status:** outline only — the measured figures are added after the assessment run and the deck is
presented then. The approval block stays unsigned until it is.

> Design rule for this deck: business language first, technology second, and never a score without
> one sentence explaining what it means. The technical detail belongs in the findings register,
> which is the supporting document for this deck.

---

## Slide 1 — The risk in plain terms

**Headline:** "One careless click is currently enough to lose the whole network."

- Every workstation shares one local administrator password.
- IT uses a single administrator account for everything, including email.
- People who have left still hold the highest level of access.
- System passwords have not changed in years.

**One supporting fact** (from the market research): credential abuse is the most common way
attackers get in (22% of breaches), and ransomware reaches 88% of small-business breaches — attackers
escalate to directory control first because that is what lets them encrypt everything at once.

**Visual:** the before/after attack-path diagram (sanitized), not a wall of settings.

## Slide 2 — What we actually looked at, and how

- We ran three free, well-known assessment tools against our own directory, inside our isolated lab
  and with written authorisation.
- We scored every finding by likelihood and impact and put it in one register with an owner and a
  date.
- We did **not** run a penetration test: this maps weak settings and reachable permissions, it does
  not break in or crack passwords.
- **Visual:** the register's first page, and the risk score with its four categories.

## Slide 3 — What we fixed, and what it changes for the business

| We changed | So that |
|---|---|
| One unique, rotating local administrator password per computer | A single compromised laptop is no longer a key to every other computer |
| Separate administrator accounts per person and per tier | An admin's email or browsing can never hand over the domain |
| Elevated access removed from people who do not need it | Fewer doors left open by accident, and a written answer to "who can change the domain?" |
| Legacy protocols switched off after an audit period | A family of well-known attacks, which needs no user mistake, stops working |
| Helpdesk rights delegated instead of granted | Routine support no longer requires the highest level of access |

**Visual:** the tier diagram (Tier 0 / Tier 1 / Tier 2) with the logon arrows.

## Slide 4 — Results: the score moved

- Overall directory risk score: **[before] → [after]** (the same tool, run the same way, so the
  comparison is fair).
- Reachable paths from an ordinary account to full administrator control: **[before] → [after]**.
- Endpoints with their own managed local administrator password: **[before] → [after]**.
- Findings closed / open / formally accepted: **[counts]**.

*(Every figure on this slide is inserted from a real lab run and cites an evidence file. Until then
it stays as a placeholder — the deck is not presented with invented numbers.)*

**Visual:** two bars and one line, plus a single sentence on what the change means for the business.

## Slide 5 — What is still open, and what we need

- **Still open:** [list of findings not yet fixed, with the reason].
- **Accepted for now:** [items with a named business owner, a written reason and a review date].
- **Asks:**
  1. Confirm that administrator access is a role, not a right — IT will hold two accounts each.
  2. Department heads confirm who still needs elevated access (the business owns that decision).
  3. One out-of-hours window for the protocol changes, which are audited before enforcement.
  4. A decision on anything we recommend accepting rather than fixing.

**Reporting commitment:** one page a month — what was fixed, what is open, what was accepted and why,
and the single headline risk score.

---

## Approval

| Role | Name | Decision | Date | Signature |
|---|---|---|---|---|
| Managing Director | | | | |
| Finance Director | | | | |
| Operations Director | | | | |
| IT (preparer) | Muhammad Ibrahim Akmal | | | |

> **Unsigned by design.** The deck is an outline until the assessment has run and the real figures
> are in it; the approval block stays blank until the presentation actually happens. Halden
> Distribution Ltd. is a fictional company in an isolated home lab, and the weaknesses it describes
> were deliberately seeded so the assessment had something real to find.
