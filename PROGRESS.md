# Progress

Mode: **A (Advisor)** — the agent has no direct access to the lab VMs. Scripts, configs and docs are
written by the agent; the owner runs them and pastes back output. Change to Mode B only when the owner
grants shell access to hosts listed in `LAB-INVENTORY.md`.

Build order: **P1 → P2 → P9 → P3 → P4 → P8 → P5 → P6 → P7 → P10** (from
`docs/plan/01-candidate-fit-and-tailored-roadmap.md`, not the numeric order).

**Current position:** all ten projects have a **complete build kit** — design, phased scripts,
configs, runbooks, diagrams, business artifacts (as PDFs) and a showcase page. **No phase has been
executed in the lab yet**, so every project remains `in-progress` and every results table reads
"not measured". That is deliberate (rule R2) and enforced in CI by `site/scripts/check-honesty.mjs`.

| Project | Status | Kit complete | Started | Site page | Next action |
|---|---|---|---|---|---|
| P1 Core infrastructure | in-progress | 2026-10-02 | 2026-09-29 | in-progress | **Start here: Phase 1 on DC01** (`scripts/01-Initialize-DC01.ps1 -Stage Promote`, snapshot first) |
| P2 Identity lifecycle | in-progress | 2026-10-02 | 2026-10-02 | in-progress | Run after P1 Phases 1–4. M365 trial: start at Phase 3 and finish the cloud work inside 30 days |
| P9 Service desk / CMDB | in-progress | 2026-10-02 | 2026-10-02 | in-progress | Create OPS01; run the docker stack. Install Uptime Kuma here for the P8 heartbeat |
| P3 AD security | in-progress | 2026-10-02 | 2026-10-02 | in-progress | Needs written authorisation before the assessment; gate script refuses without it |
| P4 Endpoint hardening | in-progress | 2026-10-02 | 2026-10-02 | in-progress | Run after P3 (LAPS and tiering); audit-mode ASR first |
| P8 Backup & DR | in-progress | 2026-10-02 | 2026-10-02 | in-progress | Create BKP01 + a second storage destination; run the first restore test before trusting it |
| P5 Patch & vuln management | in-progress | 2026-10-02 | 2026-10-02 | in-progress | LNX01 scanner; first Greenbone feed sync takes hours — start it early |
| P6 Network, VPN & Wi-Fi | in-progress | 2026-10-02 | 2026-10-02 | in-progress | Needs the VLAN-aware bridge, FW02 and CA01; owner approval required for network changes |
| P7 SIEM & IR | in-progress | 2026-10-02 | 2026-10-02 | in-progress | Heaviest RAM load (SIEM01 6 GB): power off FS01/WS02/OPS01 while it runs |
| P10 Governance & reporting | in-progress | 2026-10-02 | 2026-10-02 | in-progress | Runs continuously alongside the others; the CIS assessment is the closing exercise |

## Definition of Done — open items

All ten projects share the same four open items, because what remains is **execution**, not authoring:

| # | Open item | Applies to |
|---|---|---|
| 1 | Run each phase and record every success criterion with a source file in `evidence/public/` | all 10 |
| 2 | Fill the acceptance-test tables with real results (currently "not run") | all 10 |
| 3 | Add `metrics:` to `showcase.md` from measured values, then and only then set `status: done` | all 10 |
| 4 | Owner reads and can answer each project's interview questions before an interview | all 10 |
| — | Owner approves publishing the site (R6) — preview first, then "publish" | site |
| — | Sign the permission/entitlement matrices at the first real review | P1, P2 |

## Licences and trials

| Item | Started | Expires |
|---|---|---|
| Windows Server 2025 eval (180 days) | not started | +180 days from install |
| Windows 11 Enterprise eval (90 days) | not started | +90 days from install |
| M365 Business Premium trial (30 days) | not started | **start only at P2 Phase 3** |

## What "build kit complete" verifiably means

Checked in this repository on 2026-10-02 (reproduce with the commands shown):

| Check | Command | Result |
|---|---|---|
| Python unit tests | `python3 -m unittest <each test module>` | **259 tests, all pass** |
| Shell scripts parse | `bash -n` over every `*.sh` | 45 scripts, clean |
| JSON/YAML configs | parse every `projects/**/*.{json,yml,yaml}` | 0 invalid |
| XML/SVG/drawio well-formed | parse every `*.xml`, `*.svg`, `*.drawio` | 37 files, 0 invalid |
| Business artifacts | `npm run docs:pdf:all` | **61 PDFs** built beside their Markdown source |
| Site | `npm run check && npm run build` | placeholder, alt-text and honesty checks clean; 18 pages |
| Every published metric has evidence | `node site/scripts/check-honesty.mjs` | clean — no unmeasured metric can be published |

## Session log

### 2026-09-29: repository setup + P1 Phase 0
- Done: repo skeleton per AGENTS.md Section 3, `docs/plan/` spec copy, `projects/p01-core-infrastructure/docs/00-design.md`, CV data filled with real values, checks clean.
- Evidence: none — Phase 0 writes documents only.
- Problems/fixes: `P10` plan file initially missed in the `docs/plan` copy (glob `P0*` misses `P10`); fixed the same session. `astro preview` in Astro 7 is a per-project daemon, so the CV PDF script serves `dist/` itself.

### 2026-10-02 (a): P1 build kit, tooling and CI gates
- Done: minimal-spec lab design (Hyper-V, dynamic memory, Server Core where useful); 11 lab-guarded idempotent scripts; synthetic 85-user CSV + generator; as-built doc; logical diagram (`.svg` + `.drawio`); 6 runbooks; ACL audit script; 3 business artifacts built to PDF.
- Done: `site/scripts/md-to-pdf.mjs` + `npm run docs:pdf:all` (A4 PDFs from business Markdown using the Playwright Chromium already installed); showcase asset copier now publishes `business/*.pdf`.
- Done: `site/scripts/check-honesty.mjs` — **fails the build** if a project that is not `done` declares metrics, or if any metric/document/hero/gallery path is missing. Wired into `npm run check` and the deploy gate.
- Done: CI now runs gitleaks, the honesty gate, shellcheck, PSScriptAnalyzer, JSON/YAML validation, the Python tests and a "every business doc has its PDF" check.
- Problems/fixes: `astro build` failed with `Tsconfig not found astro/tsconfigs/strict` — cause was a stray `/home/ibrahim/Downloads/tsconfig.json` left by an earlier unzip that Vite 8 resolved by walking up from `site/`. Removed; build green.

### 2026-10-02 (b): the remaining nine build kits
- Done: P2–P10 build kits, each with design, phased scripts (lab-guarded, idempotent, `-WhatIf` where they change state), configs, 4–6 runbooks, diagrams, business artifacts, support data, README (Appendix B) and a `showcase.md`.
- Done: showcase model unified across all ten (hero diagram, one document link per business artifact as PDF, `in-progress` status, cv_bullets) by `site/scripts/normalise-showcases.mjs`.
- Done: CV data updated with the real Systems skills the ten projects prove; CV PDF back to **one page** (trimmed skills ribbon and the third CV bullet of each project for print).
- Evidence: still **none** — no lab execution. Every results table says "not measured" on purpose.
- Problems/fixes: normalising the pages immediately exposed 51 document links pointing at PDFs that did not exist; the honesty gate refused to pass. Fixed by generating all business PDFs (61 now) and by renaming P6's `business/README.md` to `_index.md` so it is not published as a document.
- Next: **push to GitHub**, confirm the lab host and RAM, download the ISOs, snapshot the host, then run P1 Phase 1 (`scripts/01-Initialize-DC01.ps1 -Stage Promote`). Every later phase is then run in build order, capturing evidence as it goes.
