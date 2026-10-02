# P6 business deliverables

Everything here is written for the fictional company Halden Distribution Ltd. and converted to PDF by
the central build; the Markdown is the source. Nothing in this folder reports a measured result — the
artefacts are the business layer around the technical work, and the approval blocks are deliberately
left unsigned until a review actually happens.

| Artifact | Audience | Purpose | Website document link |
|---|---|---|---|
| `p06-exec-brief.md` | Managing Director, department heads | One page on why segmentation matters: one compromised laptop should not reach the whole company | `./p06-exec-brief.pdf` |
| `p06-network-access-policy.md` | Management (for approval) | Who may reach what, how remote access is granted, guest terms, exception process | `./p06-network-access-policy.pdf` |
| `p06-zone-service-matrix-business.md` | Managers | The same rules in business language, so a manager can check them without knowing ports | `./p06-zone-service-matrix-business.pdf` |
| `p06-guest-wifi-notice.md` | Visitors, reception | The acceptable-use notice displayed before a guest voucher is issued | `./p06-guest-wifi-notice.pdf` |
| `p06-change-record.md` | Management, change log (feeds P10) | Risk, impact, phase plan, test plan, comms plan and backout for the highest-risk change in the portfolio | `./p06-change-record.pdf` |
| `p06-remote-access-user-guide.md` | Staff working from home | 1-page setup and troubleshooting guide for the VPN with MFA | `./p06-remote-access-user-guide.pdf` |

## How these relate to the technical artefacts

| Business artifact | Technical source of truth |
|---|---|
| `p06-network-access-policy.md` | `../configs/p06-zone-rule-matrix.csv` / `.md`, `../docs/00-design.md` §4–§8 |
| `p06-zone-service-matrix-business.md` | The same rule matrix, restated without ports |
| `p06-change-record.md` | The phase plan and evidence plan in `../docs/00-design.md` §11 and §13 |
| `p06-remote-access-user-guide.md` | `../configs/p06-nps-radius-policy.md` and `../configs/p06-openvpn-server-profile.template.ovpn` |

## Converting to PDF

The central build renders these Markdown files to PDF for the website links (the site's
`documents:` entries in `../showcase.md` point at the `.pdf` files). PDFs are generated centrally —
do not hand-export them from this folder.
