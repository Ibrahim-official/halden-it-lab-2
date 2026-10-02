# Runbook — Roll out MFA and Conditional Access (report-only first)

**Applies to:** the cloud tenant (Microsoft Entra ID) · **Owner:** IT / Systems · **Window:** inside the 30-day trial
**Scripts:** `scripts/07-New-ConditionalAccessPolicies.ps1`, `scripts/08-Set-AuthenticationMethods.ps1`

> Why "report-only first": a Conditional Access policy that is wrong can lock every user — including
> you — out of the tenant. Report-only records what *would* happen without enforcing it, and the
> break-glass accounts mean there is always a way back in. This is the order that turns a risky change
> into a reviewable one.

## Order of work (do not re-order)

0. **One-off, before anything:** on the lab host, create the marker file the P2 scripts check —
   `New-Item -ItemType File -Path 'C:\halden-lab-marker' -Force` — and paste the trial tenant's
   `onmicrosoft.com` domain into `configs/lab-tenant.json` (`labTenantDomain`). The cloud scripts refuse
   to run until the signed-in tenant matches that value.
1. **Break-glass accounts first.** Create the two cloud-only break-glass accounts before any policy
   exists, and make sure they are **excluded from every CA policy** in `configs/conditional-access/`:
   ```powershell
   .\scripts\06-New-BreakGlassAccounts.ps1
   ```
   Their passwords are generated and printed once to a git-ignored file; store them in the password
   manager immediately and record the accounts in `business/p2-mfa-rollout-comms.md`.
2. **Configure authentication methods** — Microsoft Authenticator with number matching, SMS/voice
   disabled where possible, and Temporary Access Pass enabled for onboarding:
   ```powershell
   .\scripts\08-Set-AuthenticationMethods.ps1
   ```
3. **Create the policies in report-only:**
   ```powershell
   .\scripts\07-New-ConditionalAccessPolicies.ps1 -State reportOnly
   ```
   The script reads the policy JSON from `configs/conditional-access/` and ignores its `_comment`
   header. Re-running updates the existing policies rather than duplicating them.
4. **Watch the sign-in logs for a few days.** Confirm real users and real sign-ins are matched by
   CA001, and that the break-glass accounts are *not* (they must sign in with a password alone).
5. **Turn the policies on, one at a time** — CA001 (MFA) first, then CA002 (block legacy auth), then
   the admin and location policies:
   ```powershell
   .\scripts\07-New-ConditionalAccessPolicies.ps1 -State Enabled
   ```
6. **Run ScubaGear before and after** and record the pass/fail/warning counts:
   ```powershell
   .\scripts\09-Invoke-ScubaGear.ps1 -Stage before
   # ... implement ...
   .\scripts\09-Invoke-ScubaGear.ps1 -Stage after
   ```

## Verify

- **A user signs in with a password only** → prompted for MFA (CA001). Capture the sign-in log entry.
- **A legacy/IMAP client signs in** → blocked (CA002); the block is visible in the sign-in logs with
  the legacy client app.
- **A break-glass account signs in** → **not** challenged, and the sign-in is recorded for monitoring
  (P7 will alert on it).
- **Cloud Sync status** shows the last sync as successful, with the scope limited to
  `OU=Users,OU=Halden` and `_Admin`/`ServiceAccounts` excluded.
- **Admin accounts are cloud-only** — confirm none of them appear as synced objects.

## If someone is locked out

1. Sign in with a **break-glass account**.
2. Set the offending policy to report-only (`-State reportOnly`) or add the affected group/user to
   the policy's exclusions.
3. Fix the policy, re-review the sign-in log, then re-enable it.
4. Record the incident — a lock-out is a real event and belongs in the change record, not a secret.

## Rollback

- **Policies** are configuration: set them back to report-only, or delete the specific policy with
  `Remove-MgIdentityConditionalAccessPolicy -Id <id>` (the ids are printed by the script).
- **Authentication methods**: re-enable SMS/voice if MFA enrolment is blocked, and re-run
  `08-Set-AuthenticationMethods.ps1`.
- **Nothing here touches on-premises AD**, so no DC snapshot is needed for the cloud steps; the
  snapshot still happens before the AD-preparation script (`05-Prepare-HybridIdentity.ps1`).
- The 30-day trial is time-limited: if it lapses before enforcement, do **not** present the work as
  enforced. Document that the design is complete and the fallback is Entra ID Free with Security
  Defaults (tenant-wide MFA), as agreed in `docs/00-design.md` §8.
