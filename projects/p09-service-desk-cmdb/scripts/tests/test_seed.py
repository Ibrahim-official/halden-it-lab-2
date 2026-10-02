"""Unit tests for the P9 synthetic ticket generator (scripts/04-seed-synthetic-tickets.py).

Run from the project folder:
    python3 -m unittest discover -s scripts/tests -v
The tests prove the generator is deterministic and always labels its output as
synthetic; they do not measure anything (AGENTS.md rule R2).
"""

from __future__ import annotations

import datetime as dt
import importlib.util
import pathlib
import unittest

HERE = pathlib.Path(__file__).resolve().parent
SCRIPT = HERE.parent / "04-seed-synthetic-tickets.py"
CATALOGUE = HERE.parent.parent / "configs" / "glpi-cmdb-categories.json"

spec = importlib.util.spec_from_file_location("p09_seed", SCRIPT)
seed = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(seed)


class LoadCategoriesTests(unittest.TestCase):
    def test_categories_are_loaded(self) -> None:
        categories = seed.load_categories(str(CATALOGUE))
        self.assertGreater(len(categories), 0)
        self.assertIn("Password reset / unlock", categories)


class BuildTicketsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.categories = seed.load_categories(str(CATALOGUE))

    def test_count_is_exact(self) -> None:
        tickets = seed.build_tickets(150, 4, 20261002, self.categories)
        self.assertEqual(len(tickets), 150)

    def test_deterministic_for_a_fixed_seed(self) -> None:
        first = seed.build_tickets(50, 4, 20261002, self.categories)
        second = seed.build_tickets(50, 4, 20261002, self.categories)
        self.assertEqual([t["reference"] for t in first], [t["reference"] for t in second])
        self.assertEqual([t["category"] for t in first], [t["category"] for t in second])

    def test_different_seed_changes_output(self) -> None:
        first = seed.build_tickets(50, 4, 1, self.categories)
        second = seed.build_tickets(50, 4, 2, self.categories)
        self.assertNotEqual([t["category"] for t in first], [t["category"] for t in second])

    def test_every_subject_is_labelled_synthetic(self) -> None:
        tickets = seed.build_tickets(150, 4, 20261002, self.categories)
        self.assertTrue(all(t["subject"].startswith(seed.SYNTHETIC_PREFIX) for t in tickets))
        self.assertTrue(all(t["synthetic"] for t in tickets))

    def test_categories_come_from_the_config(self) -> None:
        allowed = set(self.categories)
        tickets = seed.build_tickets(150, 4, 20261002, self.categories)
        self.assertTrue({t["category"] for t in tickets}.issubset(allowed))

    def test_created_times_are_in_business_hours(self) -> None:
        tickets = seed.build_tickets(150, 4, 20261002, self.categories)
        for ticket in tickets:
            moment = dt.datetime.fromisoformat(ticket["created"])
            self.assertLess(moment.weekday(), 5)
            self.assertGreaterEqual(moment.hour, 8)
            self.assertLess(moment.hour, 18)

    def test_empty_categories_rejected(self) -> None:
        with self.assertRaises(ValueError):
            seed.build_tickets(10, 1, 1, [])

    def test_negative_count_rejected(self) -> None:
        with self.assertRaises(ValueError):
            seed.build_tickets(-1, 1, 1, self.categories)


class SummariseTests(unittest.TestCase):
    def test_summary_totals_and_labels(self) -> None:
        categories = seed.load_categories(str(CATALOGUE))
        tickets = seed.build_tickets(150, 4, 20261002, categories)
        summary = seed.summarise(tickets)
        self.assertEqual(summary["total"], 150)
        self.assertTrue(summary["synthetic"])
        self.assertEqual(sum(summary["by_priority"].values()), 150)
        self.assertTrue(set(summary["by_priority"]).issubset({"P1", "P2", "P3", "P4"}))


if __name__ == "__main__":
    unittest.main()
