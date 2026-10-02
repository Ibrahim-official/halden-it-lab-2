# Halden Distribution Ltd. — who can reach what (business view)

**For:** managers and department heads · **From:** IT · **Date:** 2026-10-02
**Companion to:** `p06-network-access-policy.md` (the policy) and `../configs/p06-zone-rule-matrix.md`
(the technical rule list)

---

## Why a diagram-free version

The technical rule list is written for engineers: it names ports and services. This page says the same
thing in business terms, so a manager can check it without needing to know what port 445 is.

## The building, in zones

Think of the network as a building with separate floors and doors that need a key card.

| Floor (zone) | Who is on it | Who can get in |
|---|---|---|
| **Server room** | The systems that hold our identity, files and backups | Staff, for the specific services they need; the warehouse, the same; IT. **Nobody else** |
| **Warehouse network** | Site 2 devices, connected by an encrypted tunnel | Warehouse staff, IT |
| **Office floor** | Staff laptops and desktops | Staff, IT |
| **IT control room** | IT's admin workstation, the virtualisation host, the backup server, switch and Wi-Fi management | **IT only.** Not guests, not devices, and **not remote staff** |
| **Visitor area** | Visitors' phones and laptops | Internet only. Visitors cannot see each other or us |
| **Equipment network** | Printers, the CCTV recorder, warehouse scanners | One shared folder for scanning, and name look-up. No internet, by design |
| **Working from home** | Staff connected through the VPN | The same as being in the office — except the IT control room, which stays closed |

## What this is designed to prevent, in plain terms

| If this happens… | …this is what it can reach |
|---|---|
| A visitor's laptop is infected | The internet connection only. Nothing at Halden |
| A staff laptop is infected by ransomware | That laptop, and the file shares that user could already open. It cannot reach the domain controllers, the backup server or the CCTV system |
| A printer or the CCTV recorder is compromised | One shared folder. It cannot reach the servers, staff laptops or the internet |
| A home worker's laptop is compromised | The same as a user in the office — and it still cannot reach IT's control room |
| Someone guesses the old Wi-Fi password | Nothing: that password no longer exists. Only devices holding a certificate from our own authority can join the corporate network |

## What staff will notice

1. **Corporate Wi-Fi:** the password is replaced by certificates. Company laptops connect automatically
   once set up; a personal phone will not connect to the corporate network at all. Visitors use the
   guest network with a voucher from reception.
2. **Working from home:** instead of a remote desktop link, there is a VPN client, a sign-in, and an
   approval on your phone. It takes about 20 seconds longer to connect and is far safer.
3. **A folder or system you used to reach may need a request.** If a tool needs access it does not
   have, raise a ticket naming the system and the reason; IT will grant the narrowest access that does
   the job and record who owns it.

## What it costs the business

- **No new licences.** The controls are configuration on systems we already run.
- **A maintenance window** outside working hours for the migration, done one zone at a time.
- **A small amount of change** for staff, mainly the Wi-Fi and the VPN sign-in.
- **One ongoing commitment:** when someone moves role or leaves, their remote access is removed at the
  same time as their account. That is already part of the joiner-mover-leaver process.

## What it deliberately does not do

- It does **not** make Halden unhackable, and it does not replace patching, backups or anti-virus.
- It does **not** protect against someone who already has valid credentials for a system they are
  allowed to use — that is what activity monitoring is for (P7).
- It **will** need occasional exceptions. Each one is written down with an owner and a review date, so
  that "temporary" does not quietly become permanent.

---

> **Status:** prepared for review. This is the business-facing view of the decisions in the rule
> matrix; the technical detail lives there and in `../docs/00-design.md`.
