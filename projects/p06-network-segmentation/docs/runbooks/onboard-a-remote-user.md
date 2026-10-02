# Runbook — On-board a remote user to the VPN (with MFA)

**Applies to:** DC01 (group membership), FS01 (NPS policy, already in place) and FW01 (the VPN server)
· **Time:** 15 minutes · **Owner:** IT Support, on a manager-approved request

## Why this runbook exists

Remote access is the single most attractive way into a company network: getting a VPN account is
worth more to an attacker than a mailbox. So remote access is a **business decision with a technical
control**, not a request IT can quietly satisfy. The control is three-layered: an AD group decides
*who*, a certificate proves *which device*, and a second factor proves *it is really them*.

## 1. Confirm the approval

The request must come with the manager's approval and a reason (working from home, on call, travel).
Access is granted per person and is reviewed quarterly — permanent VPN access for someone who no
longer needs it is exactly what the review exists to catch. See
[`../../business/p06-network-access-policy.md`](../../business/p06-network-access-policy.md).

## 2. Add the person to the VPN group

```powershell
# on DC01
Add-ADGroupMember -Identity G_VPN_Users -Members sara.khan
Get-ADGroupMember -Identity G_VPN_Users | Select-Object Name, SamAccountName
```

Nothing else decides who may connect: the NPS policy `VPN-Staff` conditions on this group, so
membership **is** the access control. When the person leaves or moves role, removing them from the
group removes the access (and P2's leaver process does that automatically).

**IT's own access is separate.** If the request is for administrative access over the VPN, the user
goes into `G_VPN_IT` instead, which maps to the `VPN-IT-Mgmt` NPS policy. That path reaches the
management zone and needs its own justification.

## 3. Issue the device certificate

1. Ensure the device has a certificate from the Halden CA (autoenrollment, or an explicit request
   from the VPN client template). Verify:
   ```powershell
   certutil -store My
   ```
2. Export the profile for that user from FW01: **VPN > OpenVPN > Client Export**, one profile per
   person. The profile contains a **private key**.

**Handling rules for the profile (this is the part people get wrong):**

- Deliver it through the agreed secure channel — never plain email, never a chat message.
- Each user gets their own profile. Never share one profile between people: the point of per-client
  certificates is that a device can be revoked individually.
- After sending it, keep the record that it was issued (who, when, which certificate).

## 4. Confirm the second factor works

- **Entra MFA path** (while a trial is active): the first VPN logon triggers an Authenticator prompt.
- **TOTP fallback** (always available): the user registers their TOTP secret with OPNsense; the
  secret is shown once, on the device, and is never written down in a ticket or a file.

Walk the user through the registration while you are on the call, and confirm the prompt actually
appears before you close the ticket.

## 5. Prove it works — from the user's side

Ask the user to connect while you watch the NPS and firewall logs:

| Check | Where | What you want to see |
|---|---|---|
| Tunnel established | FW01 VPN log | A session with an address from 192.168.70.0/24 |
| Authentication granted | NPS on FS01 | Security event **6272** (access granted) |
| They can reach the file server | On the client | `\\fs01.ad.halden.internal\Company` opens |
| They **cannot** reach management | On the client | `Test-NetConnection 192.168.40.10 -Port 3389` fails |

That last check is not a formality: it is the difference between "has a VPN" and "has a least-privilege
remote access path".

## 6. Give the user the guide

Send [`../../business/p06-remote-access-user-guide.md`](../../business/p06-remote-access-user-guide.md)
— installation, connecting, what to do when the MFA prompt does not arrive, and who to contact.

## Rollback / offboarding

```powershell
# remote access removed immediately, on the leaver's last day
Remove-ADGroupMember -Identity G_VPN_Users -Members sara.khan -Confirm:$false
# revoke the device certificate so the profile cannot be reused even if it leaked
certutil -revoke <certificate-serial-number>   # on CA01
```

Removing group membership is not sufficient on its own: a leaked profile holds a valid certificate,
so the certificate is revoked at the CA as well. Confirm afterwards that the user's next connection
attempt is rejected and that NPS logs event **6273**.
