# Runbook — Push the endpoint baseline and verify it landed

**Applies to:** DC01 (GPO) and WS01/WS02 (clients) · **Time:** 30 minutes for the pilot ring
**Owner:** IT / Systems · **Change:** CHG-2026-004 (P4 endpoint hardening)
**Target:** apply the Microsoft Security Baseline to a pilot client and *prove* it applied before it
goes anywhere near the fleet.

> Hardening that has not been verified is a hope, not a control. This runbook ends with `gpresult`
> and the compliance report, not with "the GPO is linked".

## 0. Before you start

| Check | Why |
|---|---|
| Snapshot taken: `snap-p4-ph1-before` on DC01 and the pilot client | Rollback for a bad policy is a revert, not a rebuild |
| Microsoft baseline backups unzipped somewhere **outside** the repository (for example `C:\Tools\SCT\GPOs`) | The vendor backup is never edited and licence text is not redistributed |
| `WKS - Security Baseline - v1` (the P1 placeholder) is understood, not deleted | P4 replaces its purpose; the placeholder link order matters |
| You know which GPO wins a conflict | Two policies setting the same value is how "it applied but did not take effect" happens |

## 1. Import the baseline into a new GPO

```powershell
.\scripts\01-Import-SecurityBaseline.ps1 `
  -BackupPath C:\Tools\SCT\GPOs `
  -BaselineBackupName 'MSFT Windows 11 24H2 - Computer' `
  -ComputerGpoName 'WKS - MSFT Baseline Computer - v1' `
  -OverridesGpoName 'WKS - Halden Overrides - v1' `
  -PilotOu 'OU=Pilot,OU=Workstations,OU=Computers,OU=Halden,DC=ad,DC=halden,DC=internal' `
  -WhatIf
```

Run it again without `-WhatIf` once the plan is right. The script is idempotent: existing GPOs and
links are left alone, so a second run is safe.

**Expected:** two GPOs created, both linked to the pilot OU with the overrides GPO at **order 1**
(higher precedence). A backup of each lands in `configs/gpo-backup/`, and GPO reports in
`evidence/raw/`.

## 2. Compare with the P1–P3 GPOs (do not skip this)

Open **Policy Analyzer** (Security Compliance Toolkit), load the GPO reports, and compare the new
baseline with the existing `WKS - Drive Maps - v1`, `USR - Desktop Standards - v1` and
`DOMAIN - Password & Lockout - v1`.

For **every conflict**, decide and record: which GPO should win, and why. Export the comparison.
The common ones in this lab are the screen-lock timeout (P1 desktop standards vs the baseline) and
the password policy (P3 may add a fine-grained policy later).

**Do not resolve a conflict silently.** It goes in `configs/baseline-exceptions.csv` with an owner
and a reason, or it goes in the overrides GPO with a comment.

## 3. Apply and verify on the pilot client

On the pilot client (WS02), as an administrator:

```powershell
gpupdate /force
gpresult /h C:\Temp\p04-ph1-gpresult.html
```

In the saved report, confirm:
- both new GPOs are listed under **Applied GPOs**, and the overrides GPO has the **higher precedence**;
- a sample of baseline settings appears in the **Computer Configuration** section (for example
  Defender or firewall settings);
- no GPO in the list is shown as **Denied** for a reason you cannot explain.

Then run the compliance script against the pilot:

```powershell
.\scripts\06-Get-EndpointCompliance.ps1 -ComputerName WS02
```

**Expected:** an HTML report in `reports/` with traffic lights and an overall percentage. At this
stage C4 (ASR) will legitimately fail, because Phase 2 has not run — that is correct behaviour, not
a fault. Note the failures; they are the Phase 2 to-do list.

## 4. Decide whether to widen the rollout

Leave the baseline on the pilot for **three working days**. Ask the pilot user directly whether
anything they do daily has changed (printing, a business application, a mapped drive). Then:

- no reported impact → link the GPOs to the Workstations OU and repeat step 3 on a second client;
- reported impact → identify the setting, add it to the overrides GPO with a comment and a row in the
  exceptions register, and re-test.

## 5. Record the evidence

| File | What it shows |
|---|---|
| `p04-ph1-baseline-gpo-export.xml` / `.html` | The GPO as configured |
| `p04-ph1-policy-analyzer-diff.*` | Conflicts and how they were resolved |
| `p04-ph1-gpresult.html` (or a cropped screenshot) | The policy actually applied to the client |
| `reports/endpoint-compliance-<date>.html` | Which controls pass at this point |

Put sanitized copies in `evidence/public/` and tick the matching rows in `docs/as-built.md` §2.

**Rollback:** `Remove-GPLink -Name <gpo> -Target <OU>` then re-run `gpupdate /force`. Deleting the
GPO entirely (`Remove-GPO`) is only needed if it should not exist at all. Reverting the snapshot is
the fallback if a policy change caused a problem you cannot isolate.
