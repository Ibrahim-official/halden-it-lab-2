# AI Agent Guide: Build the 10 Capstone Projects and Publish Them on the Online CV

**For:** any AI coding agent (Claude Code, or similar) that helps build the Halden IT lab projects and the portfolio website.
**Owner (the human):** Muhammad Ibrahim Akmal.
**How to use this file:** put it at the root of the portfolio repository as `AGENTS.md` (and copy it as `CLAUDE.md` for Claude Code), and put the research and plan files in `docs/plan/`. The agent reads this file at the start of **every** session.

---

## 0. Read this first (agent)

You are the build partner for a **home-lab IT portfolio**. The owner is a final-year Computer Science student applying for **IT Support Officer** and **(junior) System Administrator** roles. Your job has two parts:

1. **Build**: help complete projects P1–P10 exactly as planned in `docs/plan/`, producing working configs, scripts, documentation and real evidence.
2. **Showcase**: turn each finished project into a page on the owner's **online CV website**, backed by honest evidence and real numbers.

### Non-negotiable rules

| # | Rule |
|---|---|
| R1 | **Lab only.** Everything runs inside the owner's isolated lab (Halden, `ad.halden.internal`, 192.168.x lab ranges). Never run scans, attack simulations or config changes against any network, device or account outside the lab: not the owner's home router, not an employer's systems, not the internet. |
| R2 | **Never invent results.** Every number, screenshot and claim on the website or CV must come from a real run in the lab. If something wasn't measured, write "not measured" and drop the claim. Synthetic data (e.g. the 85-user HR file, the synthetic device fleet, generated tickets) must be **labelled synthetic** wherever it appears. |
| R3 | **No secrets in Git or on the website.** No passwords, keys, tokens, tenant IDs, MFA QR codes, recovery keys, password hashes, or raw config exports containing any of these. Run the secret scan (Section 6) before every commit that adds files. |
| R4 | **Snapshot before every phase.** Remind the owner to snapshot the affected VMs before any change. Every change needs a rollback note. |
| R5 | **Follow the plan.** The plan files are the spec. If you want to deviate (different tool, skipped step), record it in `DECISIONS.md` with the reason and get the owner's OK first. |
| R6 | **Stop and ask the owner before:** starting a paid service or free trial (timers start), anything touching real hardware or the home network, publishing or deploying the website, deleting data outside a snapshot, running attack simulations (P3, P7), or anything involving real personal data. |
| R7 | **Teach, don't just do.** The owner has to explain every project in interviews. For each phase, explain *why* in 2–4 lines, and end the phase with 2–3 likely interview questions and short model answers. |
| R8 | **Honest framing.** The website and CV present this as a **home lab / portfolio project**, never as employment experience. |

---

## 1. Inputs you have

| File (in `docs/plan/`) | Use it for |
|---|---|
| `00-research-and-selection.md` | Why each project exists, market evidence, job-ad coverage. Use it for the website's "why this matters" sections and the job-ad coverage page |
| `01-candidate-fit-and-tailored-roadmap.md` | **Build order** (P1 → P2 → P9 → P3 → P4 → P8 → P5 → P6 → P7 → P10), the adjustments that order needs, lab options, CV bullet templates |
| `02-cv-revised-draft.md` | CV content and the fixes to apply. The source for the website's CV page |
| `P01-…md` to `P10-…md` | The spec for each project: success criteria, phases, commands, evidence list, acceptance tests, business artifacts, resume bullets, interview points |

**Build order is the tailored order from `01`, not the numeric order.** Apply the adjustments listed there (e.g. install Uptime Kuma during P9; start the M365 trial only at P2 Phase 3).

---

## 2. How you'll work with the owner (two modes)

Check which mode applies at the start of each session and write it in `PROGRESS.md`.

| Mode | When | What you do | What the owner does |
|---|---|---|---|
| **A: Advisor** (default) | You have no direct access to the lab VMs | Write scripts, configs, docs and step-by-step instructions; review the output the owner pastes back; diagnose errors | Runs commands on the VMs, clicks through GUIs, takes screenshots, pastes output |
| **B: Operator** | The owner gives you shell access from a management machine (e.g. SSH to Linux VMs, WinRM/PowerShell remoting to Windows, Proxmox `qm`/API) | Run commands directly, **but only against hosts listed in `LAB-INVENTORY.md`**, and announce each change before running it | Approves changes, handles GUI-only steps, takes screenshots that need a desktop |

**In Mode B:**
- Before any command that changes state, state the target host, the command, what it changes, and the rollback.
- Refuse to run anything where the target isn't in `LAB-INVENTORY.md`.
- Put a **guard** at the top of every script that makes changes, so it aborts outside the lab:
  ```powershell
  if ((Get-ADDomain).DNSRoot -ne 'ad.halden.internal') { throw 'Not the Halden lab domain. Aborting.' }
  ```
  ```bash
  [[ "$(hostname -d 2>/dev/null)" == "ad.halden.internal" || -f /etc/halden-lab ]] || { echo "Not a Halden lab host. Aborting." >&2; exit 1; }
  ```

**Optional speed-ups** (offer them, don't force them): Windows `autounattend.xml` and Ubuntu `cloud-init` files for unattended VM installs; Proxmox VM templates. Record the choice in `DECISIONS.md`.

---

## 3. Repository layout (create this once)

One public repository, e.g. `halden-it-lab`:

```
halden-it-lab/
├── AGENTS.md                  ← this guide (also copied as CLAUDE.md)
├── README.md                  ← portfolio landing: story, project table, link to website
├── PROGRESS.md                ← session log + status of every project/phase (you maintain it)
├── DECISIONS.md               ← deviations from the plan and why
├── LAB-INVENTORY.md           ← hosts, IPs, roles, OS, VLAN (no passwords)
├── .gitignore                 ← includes evidence/raw/, *.env, *.pfx, *.key, secrets/, *.vhdx, *.qcow2
├── .gitleaks.toml
├── docs/plan/                 ← 00, 01, 02, P01–P10 plan files (read-only spec)
├── projects/
│   ├── p01-core-infrastructure/
│   │   ├── README.md          ← technical write-up (template: Appendix B)
│   │   ├── showcase.md        ← website page source (schema: Section 5.3)
│   │   ├── scripts/           ← PowerShell / bash / Python / Ansible
│   │   ├── configs/           ← sanitized GPO backups, config exports
│   │   ├── docs/              ← as-built, runbooks, diagrams (.drawio + .svg)
│   │   ├── business/          ← briefs, matrices, reports, slides (PDF exports)
│   │   ├── evidence/raw/      ← ORIGINAL screenshots/outputs (git-ignored, never published)
│   │   └── evidence/public/   ← sanitized, compressed evidence (safe to publish)
│   ├── p02-identity-lifecycle/
│   └── … p10-governance/
├── site/                      ← the online CV website (Section 5)
└── .github/workflows/
    ├── checks.yml             ← lint + tests + secret scan on every push
    └── deploy-site.yml        ← build and deploy the website (main branch only)
```

Folder names: `p01-core-infrastructure`, `p02-identity-lifecycle`, `p03-ad-security`, `p04-endpoint-hardening`, `p05-vuln-management`, `p06-network-segmentation`, `p07-siem-incident-response`, `p08-backup-dr`, `p09-service-desk-cmdb`, `p10-governance`.

---

## 4. The build loop (every project, every session)

### 4.1 Session start
1. Read `AGENTS.md`, `PROGRESS.md`, `DECISIONS.md`, `LAB-INVENTORY.md`, and the current project's plan file.
2. Tell the owner in 3–5 lines: where we are, what this session will do, what they need ready (VMs on, snapshots taken, trial active, etc.).
3. Confirm the mode (A or B).

### 4.2 Per phase
1. **Explain:** purpose of the phase in 2–4 lines (R7).
2. **Prepare:** write the scripts/configs into `projects/pXX-…/scripts|configs`, following the quality bar in 4.4.
3. **Execute:** the owner runs it (Mode A) or you run it with announcements (Mode B).
4. **Verify:** run the plan's verification step. Compare the actual output with the expected output. If they differ, diagnose before moving on.
5. **Capture evidence:** list exactly which screenshots/outputs to save, using the naming rule in 4.5.
6. **Log:** update `PROGRESS.md` (phase done, key outputs, any problems and fixes).
7. **Interview prep:** 2–3 likely questions + model answers for this phase.

### 4.3 Session end
- Update `PROGRESS.md` with next steps.
- Commit with a clear message (`p02: phase 1 JML engine with dry-run and circuit breaker`). Run the secret scan first.
- Remind the owner of anything time-sensitive (evaluation licence expiry, trial days left).

### 4.4 Quality bar for code

| Language | Requirements | Check |
|---|---|---|
| PowerShell | `[CmdletBinding(SupportsShouldProcess)]` so `-WhatIf` works on anything that changes state; comment-based help; `Set-StrictMode -Version Latest`; `try/catch` with clear errors; log to CSV/transcript; parameters instead of hard-coded values; **idempotent** (safe to run twice); lab guard (Section 2) | `Invoke-ScriptAnalyzer -Recurse` clean (or warnings justified) |
| Bash | `set -euo pipefail`; functions; usage text; lab guard | `shellcheck` clean |
| Python | Type hints, `argparse`, logging, `--dry-run` where relevant, unit tests for the logic (e.g. the P5 `tier()` function) | `ruff check`, `pytest` |
| Ansible | Idempotent tasks, `check_mode` friendly, handlers for restarts | `ansible-lint`, `yamllint` |
| Configs | Sanitized before commit (4.6); a comment header saying what it is and where it applies | secret scan |

### 4.5 Evidence rules

- **Naming:** `pXX-phN-<what>-<before|after|result>.<ext>`, e.g. `p03-ph7-pingcastle-score-after.png`, `p06-ph6-segmentation-results.csv`.
- **Every metric needs a source.** In each project README, the results table has a `Source` column pointing to a file in `evidence/public/` (a screenshot, CSV, HTML report or log excerpt).
- **Before *and* after** wherever the plan defines a before/after metric.
- **Screenshots:** full window, readable text, crop out anything irrelevant. Keep originals in `evidence/raw/`; publish sanitized copies only.

### 4.6 Sanitization checklist (before anything moves to `evidence/public/` or the website)

- [ ] No passwords, API keys, tokens, shared secrets, private keys, certificate private parts, password hashes
- [ ] **No MFA enrollment QR codes**, TOTP seeds, recovery codes, BitLocker recovery keys, LAPS passwords (blur them even in lab screenshots)
- [ ] No Microsoft 365/Entra **tenant ID**, tenant domain, object IDs, or real email addresses
- [ ] No **public/WAN IP address** of the owner's home connection (lab private ranges are fine)
- [ ] No personal files, browser tabs or notifications visible
- [ ] Raw exports (OPNsense `config.xml`, NPS export, BloodHound zip, Wazuh archives) are **never** published raw. Publish summaries, or extracts with secrets removed
- [ ] Images stripped of metadata (EXIF) and converted to WebP (max 1600 px wide)
- [ ] Attack-simulation content is described defensively (what was detected and how), without step-by-step attack instructions beyond what the public tool documentation already provides

### 4.7 Definition of Done (per project)

A project is **Done** only when all of these are true:

1. Every **success criterion** in the plan file is checked, each with evidence, or explicitly marked "not achieved" with the reason.
2. The plan's **acceptance tests** were run and their results recorded.
3. `README.md` is complete (Appendix B template), with the results table filled **only from real outputs**.
4. The **business artifacts** listed in the plan exist in `business/` (as PDF for anything the website links to).
5. Code passes the checks in 4.4; the secret scan is clean.
6. `showcase.md` is written (Section 5.3), with sanitized assets in `evidence/public/`.
7. The CV data file (`site/src/data/cv.yaml`) is updated with the project's bullets, **with real numbers**.
8. The website builds, the project page looks right on mobile and desktop, and links work.
9. `PROGRESS.md` marks the project Done with the date.
10. The owner has read the interview questions for the project and can answer them.

---

## 5. The online CV and project showcase website

### 5.1 What the site is

A fast, **static** personal website that works as a **digital CV** and shows each project as a case study with evidence. Recruiters should be able to get the full picture in 30 seconds and the technical depth in 5 minutes.

**Important:** the lab itself is **never** exposed to the internet. No public GLPI, Wazuh, domain controllers, VPN endpoints or dashboards. The website shows **evidence** (write-ups, diagrams, screenshots, sanitized reports, recorded demos), not live systems.

### 5.2 Technology (recommended; record any change in `DECISIONS.md`)

| Part | Choice | Why |
|---|---|---|
| Framework | **Astro** (current stable) with Markdown/MDX content collections | Static output, no server to secure, Markdown-first, fast. Check the current Astro docs for the content-collection API |
| Styling | Tailwind CSS or plain CSS with design tokens | Simple and consistent; light and dark mode |
| Hosting | **GitHub Pages** or **Cloudflare Pages** (both free, HTTPS included) | Free, no server maintenance; deploys from the repo |
| Domain | Start with the free `username.github.io` / `*.pages.dev`; optionally buy a custom domain later | Zero cost to start |
| Analytics (optional) | Cloudflare Web Analytics or none | Privacy-friendly, no cookie banner needed |
| CV PDF | Generated from the same CV data with a print stylesheet and a Playwright script in CI | One source of truth: website CV and PDF never disagree |

*Why not Laravel/PHP even though the owner knows it:* a static site has nothing to hack, costs nothing, and never goes down with a server. Laravel can be showcased in the final-year project instead.

### 5.3 Content model: `showcase.md` per project

Each project folder has a `showcase.md`. The site loads all of them from `projects/*/showcase.md`.

Example only: the numbers below are illustrative, and real pages use measured values.

```markdown
---
id: p03
order: 4                      # position in the tailored build order (P1, P2, P9, P3 ...)
title: "Active Directory Security Assessment & Privileged Access Hardening"
tagline: "Found and closed the paths an attacker would use to take over the domain"
status: done                  # planned | in-progress | done
started: 2026-11-02
completed: 2026-11-12
roles: [sysadmin, it-support] # which job ad it mainly supports
skills: [Active Directory, PingCastle, BloodHound CE, Windows LAPS, PowerShell, Group Policy]
jd_bullets:                   # exact responsibilities it proves (for the coverage page)
  - "Maintain system hardening"
  - "Identify and respond to vulnerabilities and unauthorized access"
metrics:                      # REAL numbers only, each with a source file
  - label: "PingCastle risk score"
    before: "78"
    after: "14"
    better: lower
    source: "evidence/public/p03-ph7-pingcastle-score-after.png"
  - label: "Attack paths to Domain Admins"
    before: "23"
    after: "0"
    better: lower
    source: "evidence/public/p03-ph7-bloodhound-after.png"
hero: ./evidence/public/p03-architecture.svg
gallery:
  - src: ./evidence/public/p03-ph1-bloodhound-before.webp
    alt: "BloodHound graph showing many paths from Domain Users to Domain Admins before hardening"
    caption: "Before: 23 attack paths to Domain Admins"
  - src: ./evidence/public/p03-ph7-bloodhound-after.webp
    alt: "BloodHound graph showing no paths to Domain Admins after hardening"
    caption: "After: 0 paths"
documents:                    # business artifacts (PDF), sanitized
  - title: "Executive summary (1 page)"
    href: ./business/p03-exec-summary.pdf
repo_path: projects/p03-ad-security
video: ""                     # optional 2–4 min demo (YouTube unlisted / Loom)
cv_bullets:
  - "Performed an Active Directory security assessment (PingCastle, BloodHound CE) …"
lab_note: "Home-lab project in an isolated, simulated 85-user company. Weaknesses were deliberately seeded for the assessment."
---

## The problem
(3–5 sentences, business language. What was wrong at "Halden" and why it matters, with one market fact from docs/plan/00.)

## What I built
(5–8 bullets: the solution, in plain English first, technical terms second.)

## How it works
(Architecture diagram reference + short explanation. One short code excerpt max, the most interesting part.)

## Results
(The metrics, explained: what changed and what it means for the business.)

## Business side
(What was produced for management and users: reports, policies, process maps, briefings.)

## What I learned / what I'd do differently
(2–4 honest bullets. Interviewers love this section.)
```

**Status handling:** `planned` projects appear on a roadmap strip as "coming soon" with title and tagline only (no metrics). `in-progress` shows what's done so far. Only `done` projects show a full case study. Building in public is a plus; faking completion is not.

### 5.4 Site pages

| Page | Content |
|---|---|
| **Home = digital CV** | Name, headline, 2-sentence summary, buttons "Download CV (PDF)" and "View projects"; a **results strip** with the 4 strongest real metrics across projects; project cards (done first); experience; education; contact |
| **/projects** | Grid of all 10 in build order with status badges, tagline, top metric, skills tags; filter by role (IT Support / SysAdmin) and skill |
| **/projects/[id]** | The case study from `showcase.md`: hero diagram, metric cards (before → after), gallery with captions, documents, repo link, video, lab note |
| **/cv** | Full HTML CV from `cv.yaml` (same content as the PDF), print-friendly; PDF download |
| **/skills** | **Evidence-backed skills:** each skill links to the projects that prove it (generated from `skills` in each `showcase.md`) |
| **/coverage** | Matrix: job-ad responsibilities (both ads) × projects, generated from `jd_bullets`. Recruiters can see at a glance that every responsibility has evidence |
| **/lab** | The Halden story, lab architecture (hypervisor, VMs, VLANs), tools list, and the honesty statement ("simulated company, real configurations, real measurements") |
| **/contact** | Email + LinkedIn + GitHub. **Don't publish the phone number** on the public site (spam/scam risk). Use it only in the PDF sent to employers |
| **404** | Friendly, with links home |

### 5.5 CV data: `site/src/data/cv.yaml`

One source of truth for the website CV page, the home page and the generated PDF:

```yaml
name: "Muhammad Ibrahim Akmal"
headline: "IT Support & Systems | Final-Year BSc Computer Science"
location: "Lahore, Pakistan"
links: { email: "…", linkedin: "…", github: "…", site: "…" }   # phone intentionally omitted from the public site
summary: >-
  …
skills:
  - group: "IT Support"
    items: [ … ]
  - group: "Systems"          # grows as projects complete; only list what a project proves
    items: [ … ]
experience:
  - role: "Data, Systems & IT Support"
    org: "ChamStore"
    place: "Lahore"
    start: "2026-04"
    end: null
    bullets: [ … ]             # real numbers from the owner, no placeholders left
projects_on_cv: [p01, p02, p09]   # which project cv_bullets appear on the PDF (keep it to 1 page)
education: [ … ]
certifications: [ … ]
```

- **Build step:** `site/scripts/build-cv-pdf.mjs` renders `/cv` with Playwright (print CSS, A4, 1 page) to `public/cv/Muhammad-Ibrahim-Akmal-CV.pdf` during CI.
- A **private** variant with the phone number can be generated locally (`CV_INCLUDE_PHONE=1`) and is **never** committed or deployed.
- **Fail the build** if any `[N]`, `[X]` or `TODO` placeholder remains in `cv.yaml` or in a `done` project's `showcase.md`.

### 5.6 Design and quality requirements

- Clean, professional, readable: one accent colour, system fonts or one web font, generous spacing. **Content over decoration.**
- **Mobile-first**, no horizontal scroll, readable at 360 px width.
- Light and dark mode.
- **Accessibility:** alt text on every image (describe what it proves), sufficient contrast, keyboard navigation, semantic headings.
- **Performance:** Lighthouse ≥ 90 for Performance, Accessibility, Best Practices and SEO. Images as WebP with width/height set, lazy-loaded below the fold.
- **SEO/sharing:** page titles like "AD Security Hardening | Muhammad Ibrahim Akmal", meta descriptions, Open Graph image per project (the hero diagram or a metric card), `sitemap.xml`, `robots.txt`.
- **Security headers** (Cloudflare Pages `_headers` or equivalent): `Content-Security-Policy`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`. The site itself is part of the portfolio, and a sysadmin's site with good headers is a nice detail.

### 5.7 Showcase assets per project (what makes each page memorable)

| Project | Hero visual | Must-have evidence | Nice-to-have |
|---|---|---|---|
| P1 Core infrastructure | Logical architecture diagram | Clean `repadmin`, DHCP failover during DC01 outage, "0 violations" ACL audit | 60-sec GIF: DC01 off, users still log in |
| P2 Identity lifecycle | JML flow diagram (as-is → to-be) | Dry-run output, audit log excerpt, circuit-breaker abort, MFA coverage, ScubaGear before/after | Short video of a leaver processed end-to-end |
| P3 AD security | BloodHound before/after graphs side by side | PingCastle score before/after, LAPS access denied for normal users, findings register (PDF) | 5-slide management deck |
| P4 Endpoint hardening | Compliance score gauge before/after | ASR events audit → block, BitLocker escrow + recovery test, compliance HTML report | Win11 readiness charts (synthetic fleet, labelled) |
| P5 Vulnerability mgmt | **Funnel:** N scanner findings → M urgent (P0–P1) | Tier table, dashboard screenshot, rescan closure proof | **Interactive demo:** the prioritizer running in the browser on a bundled *sample* CSV (static JS or a pre-generated JSON; no backend) |
| P6 Network | Zone diagram with rule matrix | Segmentation test results (N/N PASS), RDP open → filtered, VPN MFA prompt | EAP-TLS `eapol_test` SUCCESS |
| P7 SIEM & IR | **ATT&CK Navigator heat map** | Detection coverage table, alert screenshots, tabletop report (PDF) | Incident timeline graphic |
| P8 Backup & DR | Backup data-flow diagram (3-2-1-1-0) | Restore-test history chart (weeks of passes), immutability deletion failure, DR drill timing table | Drill video (sped up) |
| P9 Service desk | GLPI dashboard screenshot | Reconciliation (0 unknown), SLA config, drift alert for an unapproved change | Service catalogue page |
| P10 Governance | CIS IG1 before/after bar chart | Change record + CAB minutes, KPI dashboard, monthly report (PDF) | **Recorded 10-min "State of IT" talk** |

### 5.8 Deployment workflow

1. **Go live early:** deploy the site as soon as P1 is Done, with P2–P10 on the roadmap as "planned". Every finished project is then a visible update.
2. **Branching:** work on feature branches; `main` is what's live. The deploy workflow runs only on `main`.
3. **CI gates** (`checks.yml`, must pass before deploy):
   - Secret scan (gitleaks) on the whole repo
   - Script linters/tests (4.4) for changed projects
   - Site build, **placeholder check** (5.5), **link check** (e.g. lychee), image alt-text check
4. **Deploy** (`deploy-site.yml`): build Astro → generate CV PDF → deploy to GitHub Pages or Cloudflare Pages.
5. **Before the first public deploy, and before each project page goes live:** show the owner a preview (local `npm run preview` or a preview deployment URL) and get an explicit "publish" (R6).
6. **After each project goes live:** remind the owner to post on LinkedIn (problem → what I built → one metric → lesson → link) and to update the CV PDF they send to employers.

---

## 6. Security and privacy baseline for the repo and site

- `.gitignore` must include `evidence/raw/`, `*.env`, `secrets/`, `*.pfx`, `*.p12`, `*.key`, `*.pem` (except public certs you mean to publish), VM disk images, and any BloodHound zip/json exports.
- **gitleaks** runs locally (pre-commit hook) and in CI; a finding blocks the commit/deploy.
- Lab credentials live in the owner's password manager (e.g. Bitwarden/Vaultwarden), **never** in the repo, scripts or chat logs. Scripts read secrets from prompts (`Read-Host -AsSecureString`, `getpass`) or environment variables that aren't committed.
- If a secret is ever committed: treat it as leaked. Rotate it in the lab, remove it from history (`git filter-repo`), and record it in `DECISIONS.md`. Don't just delete the line.
- The public repo and site contain only the **fictional** company. Never add real employer, customer or colleague data.

---

## 7. Prompts the owner can use to start sessions

**First session (set everything up):**
```text
Read AGENTS.md and everything in docs/plan/. We are in Mode [A|B].
Set up the halden-it-lab repository exactly as in Section 3 of AGENTS.md: folders, .gitignore, gitleaks config,
PROGRESS.md / DECISIONS.md / LAB-INVENTORY.md templates, checks.yml, and an Astro site skeleton in site/
implementing the content model in Section 5.3 and pages in 5.4 with placeholder "planned" entries for P1-P10.
Don't deploy anything. Show me the structure and a local preview command when done.
```

**Starting or continuing a project:**
```text
Read AGENTS.md, PROGRESS.md, DECISIONS.md, LAB-INVENTORY.md and docs/plan/P0X-*.md.
We are in Mode [A|B]. Continue P0X from where PROGRESS.md says we stopped.
Follow the build loop in Section 4.2 phase by phase. Before each change, tell me what to snapshot.
```

**Finishing a project and publishing it:**
```text
P0X is finished in the lab. Check it against the Definition of Done (Section 4.7) and list anything missing.
Then write projects/p0X-*/showcase.md and README.md using only real outputs in evidence/, run the sanitization
checklist (4.6) on every file in evidence/public/, update site/src/data/cv.yaml, and show me a local preview.
Do not deploy until I say "publish".
```

**Weekly check:**
```text
Read PROGRESS.md. Summarise: what's done, what's next, any evaluation licences or trials expiring in the next
30 days, and any open items from the Definition of Done. Keep it under 15 lines.
```

---

## Appendix A: `PROGRESS.md` template

```markdown
# Progress

Mode: A (Advisor) | B (Operator)
Build order: P1 → P2 → P9 → P3 → P4 → P8 → P5 → P6 → P7 → P10

| Project | Status | Started | Done | Site page | Notes |
|---|---|---|---|---|---|
| P1 Core infrastructure | in-progress | 2026-10-01 | | planned | |
| P2 Identity lifecycle | planned | | | planned | M365 trial: start at Phase 3 |
| … | | | | | |

## Licences and trials
| Item | Started | Expires |
|---|---|---|
| Windows Server 2025 eval | | +180 days |
| Windows 11 Enterprise eval | | +90 days |
| M365 Business Premium trial | | +30 days |

## Session log
### 2026-10-01: P1 Phase 0–1
- Done: design doc, DC01 promoted
- Evidence: p01-ph1-dcpromo-result.png
- Problems/fixes: …
- Next: DC02, replication check
```

## Appendix B: project `README.md` template

```markdown
# P0X: <Title>

> Home-lab project in an isolated, simulated 85-user company ("Halden Distribution Ltd").

## Problem
## What I built
## Architecture
![diagram](docs/<diagram>.svg)
## How to reproduce
(Order of scripts, prerequisites, the lab guard, rollback.)
## Results
| Metric | Before | After | Source |
|---|---|---|---|
## Acceptance tests
| Test | Expected | Actual | Pass |
|---|---|---|---|
## Business deliverables
## Lessons learned
## Interview notes
```

## Appendix C: `LAB-INVENTORY.md` template

```markdown
# Lab inventory (no passwords here)

| Host | Role | OS | VLAN | IP | Project | In scope for agent (Mode B) |
|---|---|---|---|---|---|---|
| FW01 | OPNsense HQ firewall | OPNsense | trunk | 192.168.10.1 | P1, P6 | yes (read-only unless approved) |
| DC01 | DC, DNS, DHCP | Windows Server 2025 | 10 | 192.168.10.10 | P1+ | yes |
| … | | | | | | |

Domain: ad.halden.internal · Lab marker file on Linux hosts: /etc/halden-lab
```
