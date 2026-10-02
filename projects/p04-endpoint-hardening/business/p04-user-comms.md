# Halden Distribution Ltd. — Endpoint change: what is changing and what you will notice

**Prepared by:** Muhammad Ibrahim Akmal, IT · **For:** All staff · **Date:** 2026-10-02
**Change:** CHG-2026-004 (endpoint hardening) · **Change record:** `p04-change-record.md`
**User runbook:** `../docs/runbooks/user-device-blocked.md`

---

## What is changing

Halden's PCs have never had a written standard. We are putting one in place, so that a lost laptop is
not a data breach and a single infected PC cannot spread to the whole company. In practice, four things
change for you:

1. **Your disk gets encrypted** (BitLocker). If the device is ever lost or stolen, the data on it
   cannot be read by whoever finds it.
2. **You will not have administrator rights on the PC.** Software you need is installed by IT. Most
   software requests are handled the same day, and there is a clear process (below).
3. **Email attachments and Office macros cannot run programs.** This is the main way ransomware gets
   into a small business. If you have a genuine business macro, tell us and we will handle it
   individually rather than switching the protection off for everyone.
4. **Your device is checked automatically every day** against nine security controls. IT sees the
   result, so problems are found before they become incidents.

## Why it matters to the business

| Risk today | After this change |
|---|---|
| A lost or stolen laptop means Halden's data is gone with it | The disk is encrypted, so the data cannot be read from the device |
| Anyone can install anything and can turn protections off | Only IT can change protections, and every change is logged |
| One infected PC can spread through the company | Malicious behaviour in email attachments, macros and scripts is blocked |
| Nobody can say whether our devices are secure | One daily percentage, per control, that management can track over time |

## What you will notice, and when

| When | What you will see |
|---|---|
| During the rollout | One or two restarts, in a window agreed with your team |
| If a file or macro is blocked | A message saying it was blocked by your organisation. See the runbook; it is usually a phishing attempt, and there is a proper way to get a legitimate file reviewed |
| If you try to install software | Windows asks for administrator permission. That is expected — raise a request instead |
| If your device ever asks for a BitLocker recovery key | Call the Service Desk. Your identity will be checked before anyone helps, which is deliberate |
| Day to day | Nothing else changes. Your files, drives, printers and applications work as before |

## What you need to do

1. **Nothing on day one.** Keep working as normal.
2. **Save your work before the agreed restart** for your team's rollout window.
3. **If you need software**, raise a ticket with the software name, what you need it for, and any
   deadline. Your manager approves it, and IT installs it in the safest way. See section below.
4. **If something that used to work stops working**, tell the Service Desk. Do not look for a workaround
   — a workaround hides a real problem that we need to fix.

## Requesting software (the simple version)

1. **Raise a ticket** — software name, what it is for, deadline.
2. **Your manager approves** it as a business need.
3. **IT installs it** with the rights it needs. In most cases that is the whole story, and you never
   need administrator rights yourself.
4. **For a one-off task**, IT can grant a permission that expires by itself, rather than giving you
   permanent rights.
5. **You will always get an answer, and a reason if the answer is no.**

## Who to contact

| Situation | Contact |
|---|---|
| Software request, blocked file, blocked macro | IT Service Desk (ticket) |
| BitLocker recovery screen | IT Service Desk (phone), urgent — have your staff ID ready |
| Anything business-stopping | IT Service Desk (phone), marked "urgent" |

## Rollback

Every phase was snapshotted before it ran, and any control can be returned to a logging-only mode
within minutes. If something in this change stops legitimate work, tell us: the control will be adapted
so the business can carry on safely, rather than being switched off for everybody.

> **Lab note:** Halden Distribution Ltd. is a fictional company used for a home-lab portfolio project.
> This is the staff-facing brief that accompanies the change.
