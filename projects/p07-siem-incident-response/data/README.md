# Support data — P7 SIEM and incident response

**Everything here is for the fictional company Halden Distribution Ltd.** No real personal data,
customer data or secret material is stored in this folder (AGENTS.md R3/R6, Section 4.6).

| File | What it is |
|---|---|
| `attack-mapping.csv` | The single source of truth that maps each custom detection rule to its MITRE ATT&CK technique and tactic. `configs/detection-coverage-matrix.csv` and the ATT&CK heat-map diagram (`docs/diagrams/p07-attack-coverage.svg`) are both derived from this file, so the picture and the rules cannot drift apart. Availability checks (D14 backup failure, D15 agent silent) are listed as comments because they are not attacker behaviour. |
| `incident-timeline-template.md` | The empty timeline an analyst completes during and after an incident. It becomes the incident report and feeds the monthly summary. |

## Why there is no raw data here

Deliberately **not committed**: raw Wazuh archives, raw alert dumps, agent keys, API tokens or
certificate private keys. AGENTS.md 4.6 says Wazuh archives are never published raw. Sanitized
extracts produced by `scripts/09-Export-AlertEvidence.sh` go to `evidence/public/`; the originals
stay in `evidence/raw/`, which is git-ignored.

## How the mapping stays honest

The heat map colours a technique only where a rule exists in `configs/local_rules.xml`. It shows
**mapped** coverage, not **validated** coverage: validation is a separate result, filled in only
after an approved simulation run and recorded in `configs/detection-coverage-matrix.csv`.
