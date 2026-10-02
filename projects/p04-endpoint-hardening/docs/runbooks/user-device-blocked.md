# Runbook (user-facing) — "My device is blocked, what now?"

**Applies to:** all Halden staff using a managed PC · **Written by:** IT · **Issued with:** the P4
endpoint hardening change brief

> Plain-language runbook. It exists so that a blocked attachment or a refusal to install software
> does not turn into a phone call at 08:55, and so that staff have one clear route to a fix.

## What you might see, and what it means

| What you see | What it means | What to do |
|---|---|---|
| "This action has been blocked by your organisation" when you open an attachment | Halden now blocks executable content and macros arriving by email. This is protecting you: attachments that try to run code are almost always a phishing attempt. | Save the file, check with the sender by phone that they really sent it, and ask the Service Desk to review it. **Do not** ask someone to email it as a ZIP to get around the block. |
| Word or Excel will not run a macro | Office macros are blocked from launching other programs. It stops the most common ransomware delivery method. | Raise a ticket naming the spreadsheet and what the macro should do. If it is a business process, IT will package or rework it rather than switching protection off. |
| "You need administrator permission" when installing software | Standard accounts no longer have local admin rights. This is deliberate: admin rights can switch off every protection on the device. | Raise a software request (below). If it is a genuine business need, IT installs it for you, packaged, so you never need rights. |
| A USB stick will not run a program | Only unsigned or untrusted programs are blocked from removable media. Reading and copying files works normally. | If it is a business tool, tell the Service Desk its name and where it came from. |
| The screen is asking for a **BitLocker recovery key** | The device cannot verify that it is the same, unmodified machine (often after a firmware, BIOS or Secure Boot change). | **Do not** try again repeatedly. Call the Service Desk with your name, department, staff ID and the hostname on the screen. |
| Your laptop will not start at all | Could be hardware, could be encryption. | Call the Service Desk. Have your staff ID ready and, if possible, the code shown on the screen. |

## How to request software (the process)

1. **Raise a ticket** with: the software name, what you need it for, and the deadline that matters.
2. **Manager approval** — your line manager confirms it is a business need.
3. **IT checks the safest route**, in this order:
   - **Package and deploy it**: IT installs it with the rights it needs. Most requests end here, and
     you get the software without any admin rights.
   - **Time-limited elevation**: for a one-off task, IT can grant a named elevation that expires
     automatically. It is logged, and it does not make you a permanent administrator.
   - **Exception**: only if the first two are impossible, with a recorded risk acceptance and an
     expiry date. These are reviewed, not forgotten.
4. **You are told the outcome and the reason.** If the answer is no, ask why — the answer is usually
   about licence, security or an existing tool that already does the job.

## BitLocker: why the key is not something IT reads out casually

BitLocker encrypts the whole disk, so a lost or stolen laptop is not a data breach. The recovery key
is the only way back into an encrypted device, so IT verifies who you are before releasing one — the
same way a bank verifies you before a transfer. **Never** share your recovery key, and never email it
to anyone, including someone claiming to be from IT.

## BitLocker recovery: what you will be asked

To release a recovery key, the Service Desk will ask for:

- your full name, department and staff ID;
- the hostname shown on the recovery screen;
- confirmation that you are the registered user of that device (they may call you back on the number
  on file).

If the device holds Finance, HR or management data, or you are not its usual user, the request is
escalated before anything is released. That is expected — please do not be offended by it.

## Who to contact

| Situation | Contact |
|---|---|
| Blocked attachment, blocked macro, blocked USB tool | IT Service Desk (ticket) |
| Need software installed | IT Service Desk (ticket) → manager approval |
| BitLocker recovery screen | IT Service Desk (phone), urgent — have your staff ID ready |
| Anything business-stopping | IT Service Desk (phone), marked "urgent" |

## Rollback / if it goes wrong

Every phase of this change was snapshotted before it ran, and the rules can be put back into a
logging-only mode within minutes. If a control is stopping legitimate work, tell the Service Desk
rather than trying to work around it: a workaround hides the problem, and the control will usually be
adapted so the business can carry on safely.
