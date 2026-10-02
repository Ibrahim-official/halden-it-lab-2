"""Unit tests for the shared Windows 11 readiness rules (data/fleet_rules.py)."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

DATA_DIR = Path(__file__).resolve().parent.parent.parent / "data"
sys.path.insert(0, str(DATA_DIR))

import fleet_rules  # noqa: E402


def device(**overrides: object) -> dict[str, object]:
    base: dict[str, object] = {
        "OS": "Windows 11",
        "CPUGeneration": 13,
        "RAM_GB": 16,
        "Disk_GB": 512,
        "TPMVersion": 2.0,
        "SecureBoot": "Yes",
        "UEFI": "Yes",
    }
    base.update(overrides)
    return base


class ClassifyTests(unittest.TestCase):
    def test_modern_windows_11_is_ready(self) -> None:
        self.assertEqual(fleet_rules.classify(device()), fleet_rules.READY)

    def test_capable_windows_10_is_upgrade(self) -> None:
        self.assertEqual(fleet_rules.classify(device(OS="Windows 10", OSBuild="19045")), fleet_rules.UPGRADE)

    def test_old_cpu_is_replace(self) -> None:
        self.assertEqual(fleet_rules.classify(device(CPUGeneration=7)), fleet_rules.REPLACE)

    def test_amd_zen_generation_zero_is_replace(self) -> None:
        self.assertEqual(fleet_rules.classify(device(CPUGeneration=0, CPU="AMD GX-420GI")), fleet_rules.REPLACE)

    def test_generation_eight_is_supported(self) -> None:
        self.assertEqual(fleet_rules.classify(device(CPUGeneration=8)), fleet_rules.READY)

    def test_missing_tpm_is_replace(self) -> None:
        self.assertEqual(fleet_rules.classify(device(TPMVersion=1.2)), fleet_rules.REPLACE)

    def test_legacy_bios_is_replace(self) -> None:
        self.assertEqual(fleet_rules.classify(device(UEFI="No", SecureBoot="No")), fleet_rules.REPLACE)

    def test_low_ram_is_replace(self) -> None:
        self.assertEqual(fleet_rules.classify(device(RAM_GB=2)), fleet_rules.REPLACE)

    def test_small_disk_is_replace(self) -> None:
        self.assertEqual(fleet_rules.classify(device(Disk_GB=32)), fleet_rules.REPLACE)

    def test_windows_11_that_fails_hardware_is_replace(self) -> None:
        # A machine cannot be "ready" just because it claims Windows 11.
        self.assertEqual(fleet_rules.classify(device(TPMVersion=1.2)), fleet_rules.REPLACE)


class HelperTests(unittest.TestCase):
    def test_bool_spellings(self) -> None:
        for truthy in ("Yes", "yes", "true", True, "1", "Y"):
            self.assertTrue(fleet_rules._as_bool(truthy))
        for falsy in ("No", "no", "false", False, "0", ""):
            self.assertFalse(fleet_rules._as_bool(falsy))

    def test_hardware_failures_lists_each_reason(self) -> None:
        reasons = fleet_rules.hardware_failures(
            device(CPUGeneration=7, TPMVersion=1.2, RAM_GB=2, Disk_GB=32, UEFI="No", SecureBoot="No")
        )
        self.assertEqual(len(reasons), 6)

    def test_numbers_arrive_as_strings_from_csv(self) -> None:
        self.assertEqual(fleet_rules.classify(device(CPUGeneration="13", RAM_GB="16", TPMVersion="2.0")), fleet_rules.READY)


if __name__ == "__main__":
    unittest.main()
