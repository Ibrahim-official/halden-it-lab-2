# GPO backup folder - P4
#
# WHAT THIS FOLDER IS
#   Where scripts/01-Import-SecurityBaseline.ps1 writes the committed backups of the Halden
#   endpoint GPOs:
#     - WKS - MSFT Baseline Computer - v1
#     - WKS - Halden Overrides - v1
#     - WKS - Windows Hardening - v1
#   and where the unzipped Microsoft Security Compliance Toolkit baseline is placed before import.
#
# WHAT MUST NEVER GO IN HERE
#   - Any file containing a password, key, token or certificate private key.
#   - The Microsoft baseline zip as downloaded if it carries licence text that must not be
#     redistributed: keep the import source outside the repository (for example C:\Tools\SCT) and
#     commit only the Halden-created backups.
#   - BitLocker recovery information, LAPS passwords or any export that contains them.
#
# HOW TO POPULATE IT
#   1. Copy the unzipped toolkit folder to a location outside the repository.
#   2. Run scripts/01-Import-SecurityBaseline.ps1 with -BackupPath pointing at it.
#   3. Run the sanitization checklist (AGENTS.md 4.6) over the produced backup folder before commit.
#   4. Confirm the secret scan passes: gitleaks detect --no-git
#
# STATUS: EMPTY BY DESIGN. Lab execution is pending, so no GPO backup exists yet.
