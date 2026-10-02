# Halden Distribution Ltd. — ITSM and service desk executive brief (1 page)

**To:** Managing Director and department heads · **From:** IT (Muhammad Ibrahim Akmal)
**Date:** 2026-10-02 · **Subject:** A tracked, measurable IT support function for Halden

> Halden Distribution Ltd. is the fictional company used in this portfolio. No figure in this brief
> is a measured result — the "after" column names the metric that will be reported once the system
> has run; the values are deliberately blank.

## The problem today

Support requests arrive by email, Teams, WhatsApp and in person. Nothing is tracked, so we cannot say
how many requests we get, what keeps breaking, or whether a user waits an hour or a week. Assets are
recorded in a spreadsheet that no longer matches reality, and the firewall support contract expired
without anyone noticing. When the previous IT person left, the documentation left with them.

## What we are putting in place

- **One place to raise a request** — a self-service portal, with email and phone still accepted, and
  every request getting a reference number.
- **Published response and resolution targets** (SLAs) so staff know what to expect and IT can be
  measured against a target, on a business-hours calendar.
- **A clear escalation route** — first line, then Systems, then the supplier — with a handoff
  template so information is never lost between people.
- **An asset register that is reconciled weekly** against the network, so we know what we own and
  what is on the network.
- **A contract and licence register with renewal alerts** at 90 and 30 days, so no contract expires
  unnoticed and no licence is paid for and unused.
- **A documentation hub** where the as-built docs and runbooks live, with an owner and a review date
  on every page — knowledge that stays when a person leaves.
- **Configuration under version control**: server and firewall configuration is saved to a private
  repository every night, and a change with no approved record is flagged the next morning.

## What it costs and what it saves

The software is free and open source (GLPI, BookStack, Uptime Kuma) and runs on one small existing
server (OPS01). The saving is in the problems it prevents: an unnoticed contract renewal, an
unmanaged device on the network, licence money spent on unused seats, and the time lost to work that
is raised three times because nobody tracked the first attempt. The **licence right-sizing check** is
the clearest early saving: seats paid for versus seats in use.

## What we are asking the business to do

1. **Approve the service catalogue and the SLA targets** — these are business decisions (what we
   offer and how fast), not IT decisions.
2. **Nominate an approver per department** for access requests; access to data is approved by the
   data owner, not by IT.
3. **Ask staff to use the portal** for anything that is not work-stopping.
4. **Respond promptly to approval requests** on tickets — a waiting approval is a waiting user.

## How we will report back

A monthly one-page report: tickets by category, first-contact resolution, SLA compliance, the top
recurring issues and the permanent fixes agreed for them, plus upcoming contract and licence
renewals. The first report will state a baseline; there is no meaningful "before" number today
because nothing was tracked, and we will say so rather than invent one.

| Metric | Before | After (to be measured) |
|---|---|---|
| Requests tracked per month | not tracked | __ |
| SLA compliance | not measured | __ |
| First-contact resolution | not measured | __ |
| Assets reconciled (0 unknown-on-network) | spreadsheet, unreconciled | __ |
| Renewals missed | at least one (firewall contract) | 0 (target) |

> **Status:** drafted for the lab. The sign-off line below is **unsigned** until the business review
> actually happens.

| Approver | Role | Date | Signature / approval |
|---|---|---|---|
|  | Managing Director |  |  |
