"""Windows 11 readiness rules shared by the P4 generator, analyzer and unit tests.

SYNTHETIC DATA NOTICE
---------------------
The fleet this module classifies (`data/synthetic-fleet.csv`) is **invented** for the
fictional company Halden Distribution Ltd. It is not a real inventory and no real
personal data is used. Every count produced from it must be labelled "synthetic fleet"
wherever it appears (AGENTS.md rule R2).

The *rules* themselves are the real Microsoft Windows 11 upgrade requirements:
a supported 64-bit CPU (Intel 8th generation / AMD Zen+ or newer), TPM 2.0,
UEFI with Secure Boot, at least 4 GB RAM and at least 64 GB of system disk.
"""

from __future__ import annotations

from typing import Any, Mapping

MIN_RAM_GB = 4
MIN_DISK_GB = 64
MIN_INTEL_CORE_GENERATION = 8

READY = "ready"
UPGRADE = "upgrade"
REPLACE = "replace"

STATUS_LABELS: dict[str, str] = {
    READY: "Ready for Windows 11",
    UPGRADE: "Windows 10 on capable hardware (in-place upgrade)",
    REPLACE: "Not capable of Windows 11 (replace)",
}


def _as_bool(value: Any) -> bool:
    """Accept the several spellings a CSV export may use for a boolean."""
    if isinstance(value, bool):
        return value
    return str(value).strip().lower() in {"yes", "true", "1", "y"}


def _as_number(value: Any) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return 0.0


def hardware_failures(device: Mapping[str, Any]) -> list[str]:
    """Return the reasons a device cannot run Windows 11 (empty list = capable)."""
    failures: list[str] = []

    if _as_number(device.get("TPMVersion", 0)) < 2.0:
        failures.append("TPM 2.0 missing or disabled")
    if not _as_bool(device.get("UEFI")):
        failures.append("Legacy BIOS (no UEFI firmware mode)")
    if not _as_bool(device.get("SecureBoot")):
        failures.append("Secure Boot not enabled")

    generation = int(_as_number(device.get("CPUGeneration", 0)))
    if generation < MIN_INTEL_CORE_GENERATION:
        failures.append(
            f"CPU older than Intel 8th generation / AMD Zen+ (generation {generation})"
        )
    if _as_number(device.get("RAM_GB", 0)) < MIN_RAM_GB:
        failures.append(f"RAM below {MIN_RAM_GB} GB")
    if _as_number(device.get("Disk_GB", 0)) < MIN_DISK_GB:
        failures.append(f"System disk below {MIN_DISK_GB} GB")

    return failures


def classify(device: Mapping[str, Any]) -> str:
    """Classify one device as ``ready``, ``upgrade`` or ``replace``."""
    if hardware_failures(device):
        return REPLACE
    return READY if str(device.get("OS", "")).startswith("Windows 11") else UPGRADE
