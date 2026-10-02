# Halden Distribution Ltd. — Executive brief: endpoint hardening and Windows 11 readiness

**Prepared by:** Muhammad Ibrahim Akmal, IT · **For:** Managing Director and department heads
**Date:** 2026-10-02 · **Change:** CHG-2026-004 · **Full report:** `p04-win11-readiness-report.md`
**Device standard:** `p04-endpoint-standard.md` · **Exceptions:** `p04-asr-exceptions.md`

> This is a one-page brief for a reader who has five minutes. The detailed evidence is in the
> supporting documents and in the project folder; every number in the full report has a source file.

---

## The situation in one paragraph

Halden's PCs were set up by whoever unboxed them. Users are local administrators, so they can install
anything and switch off whatever protection gets in the way. BitLocker is off, so a lost sales laptop
becomes a data breach. Defender runs on defaults only, so the behaviour ransomware relies on is not
blocked. Around 30% of devices still run Windows 10, which has had no security updates since
October 2025. None of this is a criticism of individuals: there has simply never been a written
standard for what a Halden PC must have.

## Why this matters commercially

- **A lost laptop is a reportable incident, not an insurance claim.** Encryption is the control that
  turns a stolen device into an inconvenience.
- **Ransomware is the main risk to a business of this size.** It usually runs on an endpoint, and it
  relies on the exact behaviours — macros, scripts, credential theft — that are currently unblocked.
- **Windows 10 is unsupported.** Industry data shows about a fifth of small-business Windows devices
  were still on it in mid-2026. Unsupported means unpatched, and unpatched is what auditors and
  insurers ask about.
- **Support cost.** Without a standard, every machine is different, so every fix takes longer than it
  should.

## What we will enforce (the endpoint standard, in plain language)

1. **Every laptop's disk is encrypted**, and IT can recover it if the machine fails.
2. **Staff do not have administrator rights by default.** Software they need is installed for them by
   IT, or granted temporarily with approval — the request process takes a ticket, not a week.
3. **Email attachments and macros cannot run programs.** Genuine business macros are handled
   individually rather than switching the protection off for everyone.
4. **Devices are checked automatically every day** against nine named controls, and the result is
   reported as one percentage the business can track over time.

## What it costs

No new licence spend. The controls use Windows features Halden already owns. The real cost is staff
time: for a short period, some software requests will need to go through IT rather than being
installed by the user.

## What we are asking you to approve

| # | Decision | Owner |
|---|---|---|
| 1 | The endpoint standard (`p04-endpoint-standard.md`) as the rule for every Halden PC | Managing Director |
| 2 | Removal of standing local administrator rights, with the documented request process | Managing Director |
| 3 | The Windows 11 options in the readiness report, and the budget for the recommended option | Finance Director + Managing Director |
| 4 | Each exception in the ASR exceptions register, with an expiry date | Department head concerned |

## What happens next

1. Pilot the standard on two devices, then roll it out in rings. **Nothing is enforced fleet-wide
   before it has been proven on a pilot and its audit period has been reviewed.**
2. Bring the Windows 11 recommendation to the next management meeting as a decision, not as
   information.

> **Approval (unsigned until a review actually happens):**
> Managing Director: ................................................  Date: ................
> Finance Director: .................................................  Date: ................

> **Lab note:** Halden Distribution Ltd. is a fictional company used for a home-lab portfolio project.
> The technical work, scripts and measurements are real; this approval block represents the lab owner's
> decision, not a real customer sign-off.
