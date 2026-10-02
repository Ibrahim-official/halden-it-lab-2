# Halden Distribution Ltd. — IT change brief

**Change:** P1 Core Infrastructure Build (new domain, file services and Group Policy baseline)
**Prepared by:** Muhammad Ibrahim Akmal, IT **For:** All staff (via department heads)
**Date:** 2026-10-02 · **Change record:** `p01-change-record.md` · **Planned window:** out of hours, one evening per phase

---

## What is changing

Halden currently runs everything on one aging server. We are replacing it with a proper
foundation: two domain controllers (so a single server failure does not stop anyone logging in),
a dedicated file server, and a managed desktop policy.

## Why it matters to the business

| Risk today | After this change |
|---|---|
| One server does everything — if it dies, no logins, no IP addresses, no files | Two servers share the work; either one can be down without stopping the business |
| Everyone has Full Control on the shared drive, so a single mistake or virus can destroy any folder | Access is granted by department role. Finance files can only be opened by Finance |
| Nobody can say who can read Finance or HR data | One permission matrix, kept up to date and approved by the department head |
| Files deleted by mistake needed an IT call and a restore from tape | Staff restore their own files from "Previous Versions" in under a minute |

## What staff will notice

1. **New drive letters** appear automatically when you log in, based on your department
   (F: Finance, H: HR, S: Sales, O: Operations, G: Company-wide reading).
2. **You will only see the folders you are allowed to open.** A folder you cannot access is
   no longer visible at all, so the shared drive looks shorter and tidier.
3. **Passwords must be at least 14 characters** and accounts lock for 15 minutes after 10 wrong
   attempts. This is a deliberate security control, not a fault.
4. **Your screen will lock after 10 minutes** of inactivity. Press any key and sign back in.
5. **Home drives** are available on a hidden share; each person can only open their own folder.

## What staff need to do

- **Nothing on day one.** Sign in as normal; the new drives appear by themselves.
- **If a drive is missing**, sign out and back in once (`Ctrl+Alt+Del` → Sign out). If it is still
  missing after that, raise a ticket with the Service Desk — do not try to map it by hand.
- **If you believe you are missing access** to a folder you need, ask your **department head**
  first: they approve access, not IT (see the permission matrix).
- **If you cannot log in at all**, call the Service Desk. Please have your staff ID ready.

## Who to contact

| Situation | Contact |
|---|---|
| Missing drive, cannot sign in, file restored incorrectly | IT Service Desk (ticket) |
| Need access to a folder for your role | Your department head, then IT on the approved request |
| Anything urgent or business-stopping | IT Service Desk by phone, marked "urgent" |

## Rollback

Every phase was snapshotted before it ran and each change is reversible; if a phase had to be
reversed, the previous working state is restored from the snapshot the same evening. No user data
is deleted by this change.
