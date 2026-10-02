# Runbook — Run the P3 AD assessment

**Applies to:** DC01 (and LNX01 for the BloodHound containers) · **Time:** about half a day ·
**When:** once for the baseline (Phase 1) and again after remediation (Phase 7)

## Why

You cannot fix what you have not measured, and you cannot publish a number you did not measure.
This runbook produces the baseline that every later claim in the project depends on. It is also the
step with the clearest authorisation requirement: it uses attack-path tooling, which is run only
inside this isolated lab and only with the owner's written authorisation (AGENTS.md rule R6).

## 0. Before you start — authorisation and safety

| Step | Why |
|---|---|
| Confirm the owner has authorised this assessment and note the reference (for example `CHG-2026-004`) | Rule R6: attack-path tooling needs explicit approval even inside a lab |
| Take snapshots named `snap-p3-ph1-before` (and `snap-p3-ph7-before` for the re-run) | Rule R4 |
| Confirm the target is `ad.halden.internal` and the hosts are the lab hosts | Rule R1: never point any of this at another network |
| Confirm the change record exists and is signed by the owner | The audit trail is part of the deliverable |

The gate script will refuse to pass without the authorisation reference and the snapshot
confirmation:

```powershell
.\scripts\00-Test-AssessmentGate.ps1 -AuthorisationReference CHG-2026-004 `
  -IHaveOwnerAuthorisation -SnapshotsTaken
```

## 1. Capture the baseline with PingCastle

```powershell
# Download the free basic edition from pingcastle.com and place it in C:\Tools\PingCastle first.
.\scripts\02-Collect-PingCastle.ps1 -PingCastlePath C:\Tools\PingCastle -Phase before `
  -AuthorisationReference CHG-2026-004 -IHaveOwnerAuthorisation
```

Expected: an HTML report, an XML report and a summary CSV in `evidence/raw/`, named
`p03-ph1-pingcastle-before.*`. Record the global score and each of the four category scores
(Stale Objects, Privileged Accounts, Trusts, Anomalies) — the plan requires all four.

## 2. Run Purple Knight

Purple Knight is a GUI tool. Run it from a domain-joined lab host as an authorised admin, select
all categories, and export the report to `evidence/raw/`. Expected: a list of indicators marked
critical, warning or informational. Move every critical indicator into the findings register with
its category.

## 3. Collect with BloodHound CE

```bash
# On LNX01, start the stack (free and open source; no data leaves the lab):
cd projects/p03-ad-security/scripts
./03-Deploy-BloodHoundCE.sh --authorise
```

Then complete the first-run setup in the web UI, and collect from a domain-joined lab host:

```powershell
# SharpHound, run from a domain-joined lab host as the owner, inside the lab only.
.\SharpHound.exe --collectionmethods All --domain ad.halden.internal --outputdirectory C:\Temp\bh
```

Upload the resulting zip in the BloodHound CE UI, then run the built-in queries:

- **Shortest paths to Domain Admins** — the core before/after metric.
- **Kerberoastable users** — matches the seeded `svc-sql` finding.
- **Principals with DCSync rights**, **unconstrained delegation** — the other high-impact classes.

Take the screenshots now, while the graph is full. In Phase 7 the same queries are re-run and the
after graphs are taken from the identical view, so the comparison is honest.

Tear the stack down when finished to free RAM on the 16 GB host:

```bash
./03-Deploy-BloodHoundCE.sh --teardown
```

## 4. Build the findings register

Normalise what the three tools found into one CSV, with a 1–5 likelihood and a 1–5 impact for each
finding, then score it:

```bash
python3 scripts/04-New-FindingsRegister.py --input evidence/raw/p03-findings-normalised.csv \
  --start-date 2026-10-05
```

The priority rules (P0–P3, with escalation for findings that hand an attacker domain control) are in
`configs/p03-remediation-priority-rules.json`. Review every score by hand: the script applies the
rule, the accountable person owns the number.

## 5. Write it up for management

- `business/p03-exec-summary.md` — one page, no jargon, which risk is fixed first and when.
- `business/p03-findings-register.md` — the same register, in a form a department head can read.
- Update the change record's post-implementation section only when remediation is verified.

## Rollback

Nothing in this runbook changes a configuration: it is read-only against AD apart from starting the
BloodHound containers on LNX01. Rollback is `./03-Deploy-BloodHoundCE.sh --teardown`. The register
and the reports are ordinary files and can simply be deleted.

> **Never publish the raw output.** The PingCastle HTML, the Purple Knight export and the BloodHound
> database name internal accounts and describe exactly how the domain could be attacked. They stay
> in `evidence/raw/` (git-ignored). Publish sanitized summaries only (AGENTS.md 4.6).
