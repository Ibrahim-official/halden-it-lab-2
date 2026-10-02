# Working from home — your VPN guide (1 page)

**For:** staff with approved remote access · **From:** IT · **Date:** 2026-10-02
**Read time:** 3 minutes · **Related:** `p06-network-access-policy.md`

---

## What is changing

The old way of reaching Halden from home — a remote desktop link to the file server — has been
removed. That link was reachable from the internet, which is how most ransomware gets into a company.
It is replaced by a **VPN**: an encrypted connection you start yourself, with your normal work
password **and an approval on your phone**.

## Before you start

You need:

1. **An approved request.** Remote access is granted by your manager. If you have not been approved,
   contact IT — you cannot set this up yourself.
2. **Your work laptop** (not a personal device), fully updated.
3. **Your phone** with the authenticator app (Microsoft Authenticator, or the code app your setup
   e-mail tells you to use).
4. **The setup e-mail from IT**, which contains your personal VPN profile file. This file is unique to
   you. **Do not share it with anyone**, including colleagues.

## Setting it up (about 5 minutes, once)

1. Save the profile file from IT's e-mail. It ends in `.ovpn`.
2. Install the VPN client: on Windows, install **OpenVPN Connect** from the Microsoft Store (IT will
   tell you if the lab uses a different client).
3. Open OpenVPN Connect and import the profile: **Import Profile → File →** choose the `.ovpn` file
   you saved.
4. Connect once. You will be asked for your **work username and password**, and then for an
   **approval on your phone**, or a **6-digit code** from your authenticator app.
5. You are connected when the client shows **Connected** and a green tunnel indicator.

## Connecting to work each day

1. Open the VPN client and press **Connect**.
2. Enter your work username and password.
3. Approve the sign-in prompt on your phone (or enter the 6-digit code).
4. Open your files the usual way — `\\fs01.ad.halden.internal\Company` or your mapped drive letters.

The connection stays up while you work. When you finish for the day, press **Disconnect**.

## What you can reach, and what you cannot

| You can | You cannot |
|---|---|
| Open the company file shares you normally use | Reach IT's administration systems (by design — those are not available remotely) |
| Use the service desk portal | Use another person's profile or certificate |
| Work exactly as you would in the office for your own files | Connect from a personal or shared computer |

## Common problems

| Problem | What to do |
|---|---|
| "Authentication failed" | Check the password; three failures locks your account. If it still fails, call the service desk — do not keep trying |
| No approval prompt appears on your phone | Check you have internet on the phone; open the authenticator app manually; if it still does not appear, use the 6-digit code instead |
| "Certificate error" or "profile invalid" | Your profile is either missing or has been revoked. Contact IT for a new one |
| Connected, but no drives appear | Sign out of Windows and back in once (drive letters are applied at sign-in). If they still do not appear, raise a ticket |
| File access is slow | Check your home internet speed first. If it is fine, raise a ticket: the cause may be a path being taken the long way around |
| You lost your laptop, or think someone has your profile | **Tell IT immediately.** The profile can be cancelled and the certificate revoked so it cannot be used again |

## Your responsibilities

- Keep your laptop updated and your password to yourself.
- Do not share your profile file, and do not copy it to another computer.
- Use the VPN only for work.
- Report anything unusual — an unexpected approval prompt you did not trigger, for example. An
  unexpected MFA prompt means someone else has your password, and that is urgent.

## If you no longer need remote access

Tell your manager. Access is reviewed every quarter and removed when it is no longer needed — that is
a feature, not a punishment: an account nobody uses but everybody can use is a way in.

## Who to contact

| Situation | Contact |
|---|---|
| Cannot connect, forgot which app to use | IT service desk (ticket) |
| Suspect your password or phone has been compromised | IT service desk **immediately**, by phone, marked urgent |
| Need remote access for the first time | Your manager, then IT on the approved request |

---

> Halden Distribution Ltd. is a fictional company; this guide is a portfolio artefact. The technical
> controls it describes are real, and no measured result is claimed anywhere in it.
