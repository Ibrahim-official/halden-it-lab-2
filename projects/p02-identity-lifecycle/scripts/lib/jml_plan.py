"""Reference implementation of the Halden joiner-mover-leaver decision logic (P2).

This module is deliberately pure Python with no Active Directory dependency: it is the
unit-tested reference for the rules the PowerShell engine (`01-Invoke-HaldenJML.ps1`) applies
against the live directory. Keeping the logic here means the classify / diff / circuit-breaker
rules can be reviewed and tested without touching the lab.

Rules implemented (see ../../docs/00-design.md section 5-6):

* Joiner  - HR says Active, no AD account exists, and the start date is inside the joiner window.
* Mover   - the AD account's department or title differs from HR, or its managed groups differ
            from the role matrix (a role change and a group-only change are both "mover").
* Leaver  - HR says Leaver and the end date is today or earlier, and the account is still enabled.
* Skip    - anything already in the desired state, plus protected accounts.

Nothing here invents a value: every field comes from the caller (the HR file, the role matrix or an
AD snapshot). All data used with it in this lab is synthetic.
"""
from __future__ import annotations

import csv
from dataclasses import dataclass, field
from datetime import date, timedelta
from pathlib import Path
from typing import Dict, Iterable, List, Sequence, Tuple

DATE_FORMAT = "%Y-%m-%d"

ACTIVE = "Active"
LEAVER = "Leaver"


@dataclass(frozen=True)
class HrPerson:
    """One row of the HR source-of-truth export."""

    employee_id: str
    first: str
    last: str
    department: str
    title: str
    manager_id: str
    status: str
    start_date: date | None
    end_date: date | None

    @property
    def sam(self) -> str:
        return sam_for(self.first, self.last)


@dataclass(frozen=True)
class AdUser:
    """The subset of a live AD account the decision needs (from an offline snapshot or Get-ADUser)."""

    employee_id: str
    sam: str
    department: str
    title: str
    enabled: bool
    groups: frozenset[str] = field(default_factory=frozenset)


@dataclass(frozen=True)
class RoleRule:
    """One row of `configs/role-matrix.csv`."""

    department: str
    title_pattern: str
    groups: Tuple[str, ...]

    def matches(self, department: str, title: str) -> bool:
        if self.department.lower() != department.lower():
            return False
        pattern = self.title_pattern
        if pattern == "*":
            return True
        return pattern.strip("*").lower() in title.lower()


@dataclass(frozen=True)
class Action:
    """A planned change. `kind` is joiner, mover or leaver."""

    kind: str
    employee_id: str
    sam: str
    add_groups: Tuple[str, ...] = ()
    remove_groups: Tuple[str, ...] = ()
    detail: str = ""


@dataclass(frozen=True)
class Plan:
    actions: Tuple[Action, ...]
    orphans: Tuple[str, ...]
    skipped: Tuple[str, ...]
    protected: Tuple[str, ...]
    snapshot_total: int
    ad_total: int
    leaver_count: int
    breaker_tripped: bool
    breaker_detail: str


# --------------------------------------------------------------------------------------------- helpers

def sam_for(first: str, last: str) -> str:
    """`first.last`, lower-cased. Names are for display only; EmployeeID is the join key."""
    return f"{first}.{last}".strip().lower()


def parse_date(value: str | None) -> date | None:
    """Parse a YYYY-MM-DD value, or return None for an empty value. Raises on a non-empty bad value."""
    if value is None:
        return None
    text = value.strip()
    if not text:
        return None
    try:
        return date.fromisoformat(text)
    except ValueError as exc:  # pragma: no cover - message is asserted in tests
        raise ValueError(f"date '{text}' is not YYYY-MM-DD") from exc


def _data_lines(path: Path) -> List[str]:
    """Return the file's lines, dropping '#' comments and blank lines (the CSV header convention)."""
    lines: List[str] = []
    for raw in path.read_text(encoding="utf-8").splitlines():
        if raw.lstrip().startswith("#") or not raw.strip():
            continue
        lines.append(raw)
    return lines


def load_hr(path: Path) -> List[HrPerson]:
    """Load the HR export. Header must contain the documented columns."""
    reader = csv.DictReader(_data_lines(path))
    people: List[HrPerson] = []
    for row in reader:
        status = (row.get("Status") or "").strip()
        if status not in (ACTIVE, LEAVER):
            raise ValueError(f"EmployeeID {row.get('EmployeeID')}: Status must be Active or Leaver, got '{status}'")
        people.append(
            HrPerson(
                employee_id=(row.get("EmployeeID") or "").strip(),
                first=(row.get("First") or "").strip(),
                last=(row.get("Last") or "").strip(),
                department=(row.get("Department") or "").strip(),
                title=(row.get("Title") or "").strip(),
                manager_id=(row.get("ManagerID") or "").strip(),
                status=status,
                start_date=parse_date(row.get("StartDate")),
                end_date=parse_date(row.get("EndDate")),
            )
        )
    return people


def load_role_matrix(path: Path) -> List[RoleRule]:
    """Load `configs/role-matrix.csv`, preserving file order (first match wins)."""
    reader = csv.DictReader(_data_lines(path))
    rules: List[RoleRule] = []
    for row in reader:
        groups = tuple(g.strip() for g in (row.get("RoleGroups") or "").split(";") if g.strip())
        rules.append(
            RoleRule(
                department=(row.get("Department") or "").strip(),
                title_pattern=(row.get("Title") or "").strip(),
                groups=groups,
            )
        )
    return rules


def desired_groups(department: str, title: str, matrix: Sequence[RoleRule]) -> Tuple[str, ...]:
    """The desired role groups for a role: first matching rule wins, file order breaks ties."""
    for rule in matrix:
        if rule.matches(department, title):
            return rule.groups
    return ()


def managed_group_pool(matrix: Sequence[RoleRule]) -> frozenset[str]:
    """Every group the matrix names. The mover path only ever removes groups from this pool."""
    pool: set[str] = set()
    for rule in matrix:
        pool.update(rule.groups)
    return frozenset(pool)


def diff_groups(current: Iterable[str], desired: Iterable[str], managed: frozenset[str]) -> Tuple[Tuple[str, ...], Tuple[str, ...]]:
    """Return (groups to add, groups to remove).

    Removal is limited to `managed` groups, so a group that represents a separate approval (for
    example a project distribution list) is never revoked by the mover path. This is a deliberate
    safety choice, documented in docs/00-design.md.
    """
    current_set = set(current)
    desired_set = set(desired)
    add = tuple(sorted(desired_set - current_set))
    remove = tuple(sorted((current_set & managed) - desired_set))
    return add, remove


def classify(
    person: HrPerson,
    ad_user: AdUser | None,
    today: date,
    joiner_lead_days: int = 7,
) -> str:
    """Decide what (if anything) should happen for one person. Returns joiner, mover, leaver or skip."""
    if person.status == LEAVER:
        if ad_user is None:
            return "skip"
        if not ad_user.enabled:
            return "skip"
        if person.end_date is not None and person.end_date <= today:
            return "leaver"
        return "skip"

    if ad_user is None:
        if person.start_date is None:
            return "skip"
        window_end = today + timedelta(days=joiner_lead_days)
        if person.start_date <= window_end:
            return "joiner"
        return "skip"

    if ad_user.department != person.department or ad_user.title != person.title:
        return "mover"
    return "skip"


def breaker_tripped(run_leaver_count: int, snapshot_total: int, percent: float) -> bool:
    """True when *this run* would disable more than `percent` of the accounts in the HR snapshot.

    Both arguments are counts over the same population - the accounts the export covers - so the
    ratio is meaningful. The earlier draft compared this run's leavers against the number of
    accounts actually present in AD, which made a small demonstration export trip the breaker on a
    single genuine leaver; the two counts must share a denominator.
    """
    if snapshot_total <= 0:
        return False
    return run_leaver_count > (snapshot_total * percent / 100.0)


def build_plan(
    people: Sequence[HrPerson],
    ad_users: Sequence[AdUser],
    matrix: Sequence[RoleRule],
    today: date,
    joiner_lead_days: int = 7,
    protected: Iterable[str] = (),
    circuit_breaker_percent: float = 10.0,
) -> Plan:
    """Reconcile HR against AD and return the complete, reviewable plan."""
    ad_by_id: Dict[str, AdUser] = {u.employee_id: u for u in ad_users if u.employee_id}
    protected_set = {name.strip().lower() for name in protected if name.strip()}
    managed = managed_group_pool(matrix)

    actions: List[Action] = []
    skipped: List[str] = []
    protected_hits: List[str] = []

    for person in people:
        ad_user = ad_by_id.get(person.employee_id)
        sam = ad_user.sam if ad_user else person.sam

        if sam.lower() in protected_set:
            protected_hits.append(sam)
            skipped.append(f"{person.employee_id}:protected")
            continue

        kind = classify(person, ad_user, today, joiner_lead_days)
        if kind == "skip":
            skipped.append(f"{person.employee_id}:in-desired-state")
            continue

        if kind == "joiner":
            actions.append(
                Action(
                    kind="joiner",
                    employee_id=person.employee_id,
                    sam=person.sam,
                    add_groups=desired_groups(person.department, person.title, matrix),
                    detail=f"{person.department}/{person.title}",
                )
            )
        elif kind == "mover":
            assert ad_user is not None
            add, remove = diff_groups(
                ad_user.groups,
                desired_groups(person.department, person.title, matrix),
                managed,
            )
            actions.append(
                Action(
                    kind="mover",
                    employee_id=person.employee_id,
                    sam=ad_user.sam,
                    add_groups=add,
                    remove_groups=remove,
                    detail=f"{ad_user.department}/{ad_user.title} -> {person.department}/{person.title}",
                )
            )
        elif kind == "leaver":
            actions.append(
                Action(
                    kind="leaver",
                    employee_id=person.employee_id,
                    sam=sam,
                    detail=f"end date {person.end_date.isoformat() if person.end_date else 'unknown'}",
                )
            )

    hr_ids = {person.employee_id for person in people}
    orphans = tuple(sorted(u.sam for u in ad_users if u.enabled and u.employee_id not in hr_ids))

    leaver_count = sum(1 for a in actions if a.kind == "leaver")
    # The denominator is the population this export covers, so the breaker ratio answers the right
    # question: "would this run disable a large share of the people HR told me about?"
    snapshot_total = len(people)
    tripped = breaker_tripped(leaver_count, snapshot_total, circuit_breaker_percent)
    detail = (
        f"{leaver_count} leaver(s) of {snapshot_total} account(s) in this export "
        f"= {'over' if tripped else 'within'} the {circuit_breaker_percent:g}% limit "
        f"(threshold: more than {snapshot_total * circuit_breaker_percent / 100.0:.2f})"
    )

    return Plan(
        actions=tuple(actions),
        orphans=orphans,
        skipped=tuple(skipped),
        protected=tuple(protected_hits),
        snapshot_total=snapshot_total,
        ad_total=len(ad_users),
        leaver_count=leaver_count,
        breaker_tripped=tripped,
        breaker_detail=detail,
    )
