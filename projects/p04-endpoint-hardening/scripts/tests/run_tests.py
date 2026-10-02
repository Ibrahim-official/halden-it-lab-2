"""Run the P4 Python unit tests with the standard library (pytest is not required).

Usage:
    python3 scripts/tests/run_tests.py

The same test modules also run under pytest if it is installed:
    pytest scripts/tests
"""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

TESTS_DIR = Path(__file__).resolve().parent
SCRIPTS_DIR = TESTS_DIR.parent
DATA_DIR = SCRIPTS_DIR.parent / "data"

for path in (SCRIPTS_DIR, DATA_DIR):
    if str(path) not in sys.path:
        sys.path.insert(0, str(path))


def main() -> int:
    suite = unittest.defaultTestLoader.discover(start_dir=str(TESTS_DIR), pattern="test_*.py")
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    return 0 if result.wasSuccessful() else 1


if __name__ == "__main__":
    raise SystemExit(main())
