# Halden Distribution Ltd. — vendor management procedure

**Purpose:** how external suppliers are engaged, given access, reviewed and held to account, so the
business knows who its vendors are and what they can reach.
**Owner:** IT (Muhammad Ibrahim Akmal) · **Approver:** Managing Director · **Review:** annually

> Halden Distribution Ltd. is the fictional company used in this portfolio; **every supplier named
> here is invented**. Market context: third-party involvement in breaches doubled to 30%
> (Verizon DBIR 2025, finding 3 in `docs/plan/00-research-and-selection.md`), which is why vendor
> records and contracts are part of the security work, not only the administrative work.

## 1. Scope

Applies to every supplier that provides IT hardware, software, connectivity, hosted services,
backup, or an incident-response retainer. These are synthetic Halden suppliers:

| Supplier (fictional) | Provides | Contract concern |
|---|---|---|
| Northwind Technology | Hardware and warranty | Warranty terms, response times |
| Contoso Connect | ISP / connectivity | Line SLA, escalation path |
| Fabrikam Firewall Systems | Firewall appliance and support | Support contract renewal date |
| Contoso Cloud Reseller | Microsoft 365 licensing | Seat count, renewal, price |
| Fabrikam Offsite Backup | Offsite backup repository | Data residency, recovery test evidence |
| Litware Security (MSP) | Incident-response retainer | Retainer scope, activation route |
| Tasman Print Services | Managed print lease | Consumables, break-fix response |

## 2. The vendor register

Every supplier has a record in GLPI (Suppliers) linked to the assets it covers and carrying:

- Account number and support phone/portal.
- Contract start, end, **notice period**, cost and auto-renew flag.
- Named escalation contact and the provider's own response commitment.
- The **renewal alerts** at **90 days** and **30 days** before the notice date — no contract
  expires unnoticed again, which is exactly what happened to the firewall support contract.

## 3. Raising and tracking a vendor case

1. Raise it as a ticket **linked to the supplier record** (see the escalation matrix handoff
   template in [`p09-escalation-matrix.md`](./p09-escalation-matrix.md)).
2. Include the account number, serial or service reference, and the agreed support window.
3. Record the provider's reference number on the ticket; chase by the contract's response terms,
   not by hoping.
4. Close only when the requester confirms the outcome, and note the resolution for the next review.

## 4. Vendor access to Halden systems

- Access is **time-bound**: created for a specific case, disabled when the case closes.
- Access is **MFA-protected** and where possible reaches only the specific system involved.
- All vendor sessions are **logged** and reviewed at the annual review.
- Vendors never receive a standing administrative account. This is the same least-privilege rule
  as for staff (P1/P3).

## 5. Annual vendor review

At least once a year, review each supplier against:

- Security posture questions (do they hold our data, where, and with what controls? breach history?).
- Performance against the contract (response times, incidents, escalations).
- Value and cost (are we still using what we pay for — the licence right-sizing check in P9?).
- Continued need (is the service still required at all?).

## 6. Records and secrets

Supplier contacts, contract dates and support references are stored in the register and summarised
in the BookStack "Vendors" shelf. **Passwords, portal credentials and API keys are never stored in
the wiki or this document** — they live in the password manager with a shared collection for IT.

> **Status:** designed for the lab; no contract, contact or renewal figure here has been measured or
> confirmed against a real supplier (there are none — the company and the vendors are fictional).
