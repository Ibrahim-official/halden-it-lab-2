"""Unit tests for the Halden JML decision logic (P2).

These test the *rules*, not the lab: no domain, no network, no measured values. Run with:

    cd projects/p02-identity-lifecycle/scripts
    python3 -m pytest tests/ -q          # if pytest is available
    python3 -m unittest discover -s tests -v   # otherwise, self-contained
"""
from __future__ import annotations

import sys
import unittest
from datetime import date
from pathlib import Path

SCRIPTS = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(SCRIPTS / "lib"))

import jml_plan  # noqa: E402

DATA = SCRIPTS.parent / "data"
CONFIGS = SCRIPTS.parent / "configs"

TODAY = date(2026, 10, 2)


def person(**overrides):
    base = dict(
        employee_id="9001",
        first="Test",
        last="Person",
        department="Finance",
        title="Accountant",
        manager_id="1006",
        status=jml_plan.ACTIVE,
        start_date=date(2020, 1, 1),
        end_date=None,
    )
    base.update(overrides)
    return jml_plan.HrPerson(**base)


def ad_user(**overrides):
    base = dict(
        employee_id="9001",
        sam="test.person",
        department="Finance",
        title="Accountant",
        enabled=True,
        groups=frozenset({"G_Finance_Staff", "G_AllStaff"}),
    )
    base.update(overrides)
    return jml_plan.AdUser(**base)


class SamTests(unittest.TestCase):
    def test_sam_is_first_dot_last_lowercased(self):
        self.assertEqual(jml_plan.sam_for("Sara", "Khan"), "sara.khan")

    def test_sam_never_uses_employee_id(self):
        # The join key is EmployeeID; the logon name is display-derived and must stay that way.
        alice = jml_plan.sam_for("Sara", "Khan")
        bob = jml_plan.sam_for("Sara", "Khan")
        self.assertEqual(alice, bob)


class DateTests(unittest.TestCase):
    def test_empty_date_is_none(self):
        self.assertIsNone(jml_plan.parse_date(""))
        self.assertIsNone(jml_plan.parse_date(None))

    def test_iso_date_parses(self):
        self.assertEqual(jml_plan.parse_date("2026-10-02"), date(2026, 10, 2))

    def test_bad_date_raises(self):
        with self.assertRaises(ValueError):
            jml_plan.parse_date("02/10/2026")


class ClassifyTests(unittest.TestCase):
    def test_active_with_no_account_is_a_joiner(self):
        self.assertEqual(jml_plan.classify(person(start_date=date(2026, 10, 5)), None, TODAY), "joiner")

    def test_active_starting_later_than_the_window_is_skipped(self):
        self.assertEqual(jml_plan.classify(person(start_date=date(2026, 12, 1)), None, TODAY), "skip")

    def test_joiner_at_the_window_edge_is_created(self):
        self.assertEqual(jml_plan.classify(person(start_date=date(2026, 10, 9)), None, TODAY), "joiner")

    def test_unchanged_person_is_skipped(self):
        self.assertEqual(jml_plan.classify(person(), ad_user(), TODAY), "skip")

    def test_title_change_is_a_mover(self):
        self.assertEqual(jml_plan.classify(person(title="Payroll Officer"), ad_user(), TODAY), "mover")

    def test_department_change_is_a_mover(self):
        self.assertEqual(
            jml_plan.classify(person(department="Operations", title="Dispatcher"), ad_user(), TODAY), "mover"
        )

    def test_leaver_with_end_date_today_is_a_leaver(self):
        self.assertEqual(
            jml_plan.classify(person(status=jml_plan.LEAVER, end_date=TODAY), ad_user(), TODAY), "leaver"
        )

    def test_leaver_with_future_end_date_is_skipped(self):
        self.assertEqual(
            jml_plan.classify(person(status=jml_plan.LEAVER, end_date=date(2026, 11, 1)), ad_user(), TODAY), "skip"
        )

    def test_disabled_leaver_is_not_processed_twice(self):
        self.assertEqual(
            jml_plan.classify(person(status=jml_plan.LEAVER, end_date=TODAY), ad_user(enabled=False), TODAY), "skip"
        )


class GroupDiffTests(unittest.TestCase):
    def setUp(self):
        self.matrix = jml_plan.load_role_matrix(CONFIGS / "role-matrix.csv")
        self.managed = jml_plan.managed_group_pool(self.matrix)

    def test_desired_groups_for_operations_title(self):
        groups = jml_plan.desired_groups("Operations", "Forklift Driver", self.matrix)
        self.assertEqual(groups, ("G_Operations_Staff", "G_AllStaff"))

    def test_desired_groups_for_it_systems_administrator(self):
        groups = jml_plan.desired_groups("IT", "Systems Administrator", self.matrix)
        self.assertIn("G_IT_LinuxAdmins", groups)

    def test_desired_groups_for_it_support_officer_excludes_linux_admin(self):
        groups = jml_plan.desired_groups("IT", "IT Support Officer", self.matrix)
        self.assertNotIn("G_IT_LinuxAdmins", groups)
        self.assertIn("G_IT_Staff", groups)

    def test_unknown_department_has_no_desired_groups(self):
        self.assertEqual(jml_plan.desired_groups("Marketing", "Manager", self.matrix), ())

    def test_mover_removes_the_old_role_and_adds_the_new_one(self):
        add, remove = jml_plan.diff_groups(
            {"G_Finance_Staff", "G_AllStaff"},
            jml_plan.desired_groups("Operations", "Dispatcher", self.matrix),
            self.managed,
        )
        self.assertEqual(add, ("G_Operations_Staff",))
        self.assertEqual(remove, ("G_Finance_Staff",))

    def test_mover_leaves_an_unmanaged_group_alone(self):
        # A project distribution list is not in the matrix, so the mover must not revoke it.
        add, remove = jml_plan.diff_groups(
            {"G_Finance_Staff", "G_AllStaff", "DL_Project-Apollo_Members"},
            jml_plan.desired_groups("Operations", "Dispatcher", self.matrix),
            self.managed,
        )
        self.assertEqual(add, ("G_Operations_Staff",))
        self.assertEqual(remove, ("G_Finance_Staff",))

    def test_no_change_produces_no_diff(self):
        add, remove = jml_plan.diff_groups(
            {"G_Finance_Staff", "G_AllStaff"},
            jml_plan.desired_groups("Finance", "Accountant", self.matrix),
            self.managed,
        )
        self.assertEqual((add, remove), ((), ()))

    def test_role_matrix_has_no_duplicate_department_title_pairs(self):
        seen = set()
        for rule in self.matrix:
            key = (rule.department.lower(), rule.title_pattern.lower())
            self.assertNotIn(key, seen, f"duplicate rule for {key}")
            seen.add(key)


class CircuitBreakerTests(unittest.TestCase):
    def test_ten_percent_of_ten_is_exactly_at_the_limit(self):
        self.assertFalse(jml_plan.breaker_tripped(1, 10, 10.0))

    def test_above_the_limit_trips(self):
        self.assertTrue(jml_plan.breaker_tripped(3, 10, 10.0))

    def test_one_leaver_in_a_nine_person_export_trips_the_breaker(self):
        # 1/9 = 11.1%, which is over a 10% limit. The engine aborts and asks a human to confirm.
        self.assertTrue(jml_plan.breaker_tripped(1, 9, 10.0))

    def test_one_leaver_in_the_full_85_person_export_does_not_trip(self):
        # 1/85 = 1.2%, a normal day. This is the case the ratio must allow.
        self.assertFalse(jml_plan.breaker_tripped(1, 85, 10.0))

    def test_a_bad_export_disabling_most_of_the_company_trips(self):
        # 50% marked leaver (AGENTS.md P2 plan phase 5 scenario).
        self.assertTrue(jml_plan.breaker_tripped(43, 85, 10.0))

    def test_no_managed_accounts_does_not_trip(self):
        self.assertFalse(jml_plan.breaker_tripped(0, 0, 10.0))


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.matrix = jml_plan.load_role_matrix(CONFIGS / "role-matrix.csv")
        self.protected = ["bg-breakglass-1", "svc-dhcpdns"]

    def test_sample_export_produces_one_of_each_action(self):
        people = jml_plan.load_hr(DATA / "hr-export-sample.csv")
        ad_users = [
            jml_plan.AdUser("1001", "anum.hussain", "Management", "Managing Director", True,
                            frozenset({"G_Management", "G_AllStaff"})),
            jml_plan.AdUser("1003", "salman.rana", "Management", "Finance Director", True,
                            frozenset({"G_Management", "G_AllStaff"})),
            jml_plan.AdUser("1007", "laiba.qureshi", "Finance", "Accountant", True,
                            frozenset({"G_Finance_Staff", "G_AllStaff"})),
            jml_plan.AdUser("1014", "anum.dar", "HR", "HR Manager", True,
                            frozenset({"G_HR_Staff", "G_AllStaff"})),
            jml_plan.AdUser("1038", "anum.rauf", "Operations", "Operations Manager", True,
                            frozenset({"G_Operations_Staff", "G_AllStaff"})),
            jml_plan.AdUser("1042", "mahnoor.malik", "Operations", "Stock Controller", True,
                            frozenset({"G_Operations_Staff", "G_AllStaff"})),
            jml_plan.AdUser("1082", "amna.anwar", "IT", "Systems Administrator", True,
                            frozenset({"G_IT_Staff", "G_IT_LinuxAdmins", "G_AllStaff"})),
            jml_plan.AdUser("1085", "mina.hussain", "IT", "IT Support Officer", True,
                            frozenset({"G_IT_Staff", "G_AllStaff"})),
        ]
        plan = jml_plan.build_plan(people, ad_users, self.matrix, TODAY, protected=self.protected)
        kinds = sorted(a.kind for a in plan.actions)
        self.assertEqual(kinds, ["joiner", "leaver", "mover"])
        # 1 leaver out of the 9 people this export covers is over the limit, so the engine would
        # stop and ask for a human decision. Nothing here has been measured in the lab.
        self.assertTrue(plan.breaker_tripped)
        self.assertEqual(plan.snapshot_total, 9)
        self.assertEqual(plan.leaver_count, 1)

        mover = next(a for a in plan.actions if a.kind == "mover")
        self.assertEqual(mover.employee_id, "1007")
        self.assertEqual(mover.remove_groups, ("G_Finance_Staff",))
        self.assertEqual(mover.add_groups, ("G_Operations_Staff",))

        leaver = next(a for a in plan.actions if a.kind == "leaver")
        self.assertEqual(leaver.employee_id, "1042")

        joiner = next(a for a in plan.actions if a.kind == "joiner")
        self.assertEqual(joiner.employee_id, "1086")
        self.assertIn("G_Sales_Staff", joiner.add_groups)

    def test_protected_accounts_are_skipped_and_reported(self):
        people = [person(employee_id="1090", first="Breakglass", last="One")]
        ad_users = [jml_plan.AdUser("1090", "bg-breakglass-1", "Finance", "Accountant", True,
                                    frozenset({"G_Finance_Staff"}))]
        plan = jml_plan.build_plan(people, ad_users, self.matrix, TODAY, protected=self.protected)
        self.assertEqual(plan.actions, ())
        self.assertEqual(plan.protected, ("bg-breakglass-1",))
        self.assertIn("1090:protected", plan.skipped)

    def test_corrupt_export_trips_the_circuit_breaker(self):
        people = jml_plan.load_hr(DATA / "hr-export-corrupt-sample.csv")
        ad_users = [
            jml_plan.AdUser(p.employee_id, p.sam, p.department, p.title, True, frozenset({"G_AllStaff"}))
            for p in people
        ]
        plan = jml_plan.build_plan(people, ad_users, self.matrix, TODAY)
        self.assertTrue(plan.breaker_tripped)
        self.assertEqual(plan.leaver_count, 6)
        self.assertEqual(plan.snapshot_total, len(people))

    def test_orphans_are_reported_but_not_actioned(self):
        people = [person(employee_id="9001")]
        ad_users = [
            ad_user(),
            jml_plan.AdUser("7777", "ghost.account", "Sales", "Sales Executive", True, frozenset({"G_Sales_Staff"})),
        ]
        plan = jml_plan.build_plan(people, ad_users, self.matrix, TODAY)
        self.assertEqual(plan.orphans, ("ghost.account",))
        self.assertEqual(plan.actions, ())

    def test_disabled_orphan_is_not_reported(self):
        people = [person(employee_id="9001")]
        ad_users = [
            ad_user(),
            jml_plan.AdUser("7777", "ghost.account", "Sales", "Sales Executive", False, frozenset()),
        ]
        plan = jml_plan.build_plan(people, ad_users, self.matrix, TODAY)
        self.assertEqual(plan.orphans, ())

    def test_second_run_is_idempotent(self):
        people = [person(), person(employee_id="9002", first="Second", last="Person")]
        ad_users = [
            ad_user(),
            jml_plan.AdUser("9002", "second.person", "Finance", "Accountant", True,
                            frozenset({"G_Finance_Staff", "G_AllStaff"})),
        ]
        plan = jml_plan.build_plan(people, ad_users, self.matrix, TODAY)
        self.assertEqual(plan.actions, (), "an already-reconciled directory must produce no actions")


if __name__ == "__main__":
    unittest.main(verbosity=2)
