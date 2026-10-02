# Halden Distribution Ltd. — IT service catalogue

**Purpose:** the single list of what IT provides, who can ask for it, who approves it and how long
it should take. **Owner:** IT (Muhammad Ibrahim Akmal) · **Approvers:** department heads and the
Managing Director · **Review:** quarterly, plus whenever a service is added or removed.

**How to read it:** "Approval" is the person whose decision it is to grant the service — access to
business data is a business decision, not an IT decision. "Target" is the time from a complete,
approved request to the outcome, measured in **business hours** (Mon–Fri 08:00–18:00).

| Service | Request type | Approval | Target |
|---|---|---|---|
| New starter setup | Form (HR) | HR + hiring manager | Ready the business day before the start date |
| Leaver / offboarding | Form (HR) | HR | Within 1 hour of the HR notification |
| Software installation | Form | Line manager (+ IT if the title is not approved) | 2 business days |
| VPN access | Form | Line manager | 1 business day |
| Shared folder access | Form | Data owner (department head) | 1 business day |
| Hardware request | Form | Line manager + budget holder | Quote in 3 business days |
| Incident (something is broken) | Portal / email / phone | — | Per the priority SLA |
| Report a phishing email | Form / email | — | Acknowledge in 1 hour |
| Restore a file or folder | Form | — | Self-service immediate; request 2 business days |

Notes:

- **Approvals are recorded on the ticket.** An approval given verbally is not an approval; the
  ticket holds the decision so the audit trail exists.
- **Access to business data** (folder access, and the new-starter access list) is approved by the
  **data owner**, not by IT. IT implements; the business owns the decision.
- This machine-readable version of the catalogue is `configs/glpi-service-catalogue.json`; the
  human-readable version is this document. They must be kept in step.

## Service detail

**New starter setup.** HR submits the form with name, department, title, start date, office and
manager. The ticket routes to IT with a task that references the automated joiner process
(P2) so nothing is created by hand. Access is granted by department role through the group model;
the new starter receives credentials by the agreed secure channel, never by email in clear text.

**Leaver / offboarding.** HR submits the form; IT disables the account, removes access, records the
equipment returned and hands over business data to the manager. The target is one hour because an
open account after someone leaves is an access risk, not an administrative delay.

**Software installation.** Approved titles install on request. Anything not on the approved list
goes to IT for a review first (licence, security and supportability), which is why the approval
column names IT as a second approver.

**VPN access.** For approved remote or travelling staff only. Access is MFA-protected (P6); a
request without a manager's approval is not granted.

**Shared folder access.** Granted through the role-group model (P1); no individual is ever placed on
a folder. Read-only access across departments needs the owning department head's approval.

**Hardware request.** A quote is produced within three business days; purchase then follows the
normal budget approval. IT does not approve spending.

**Incident.** A fault, not a request: routed by priority per the SLA policy. Users are encouraged to
use the portal, but email and phone remain valid channels so nothing is missed.

**Report a phishing email.** Always triaged by L2 (Systems), never left in the L1 queue, and
acknowledged within an hour so the reporter knows it was seen.

**Restore a file or folder.** Self-service through Previous Versions where possible; otherwise a
restore request routed to the backup service (P8).

## Business approval

The catalogue is a commitment from IT to the business and from the business to IT (approvers must
respond promptly). Please confirm your department's services and targets below; unsigned rows are
reviewed at the next quarterly review.

| Department | Approver name | Role | Date | Signature / approval |
|---|---|---|---|---|
| Management |  | Managing Director |  |  |
| Finance |  | Finance Director |  |  |
| HR |  | HR Director |  |  |
| Sales |  | Sales Director |  |  |
| Operations / Warehouse |  | Operations Director |  |  |
| IT |  | IT Manager |  |  |

> **Status:** designed for the lab; **the approval column is unsigned** until the department-head
> review actually happens. It is deliberately left blank rather than pre-filled. Halden Distribution
> Ltd. is the fictional company used for this portfolio.
