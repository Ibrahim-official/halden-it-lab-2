#!/usr/bin/env python3
"""P9 Phase 2: generate SYNTHETIC support tickets for the service-desk simulation.

What
    Produces a realistic-looking set of support requests (~150 over 4 simulated
    weeks by default) so the GLPI reports have data to render. Every subject is
    prefixed ``[SYNTHETIC]`` and every requester is an invented Halden user.
    Nothing here is real: the tickets are generated, not measured, and must be
    labelled synthetic wherever they appear (AGENTS.md rule R2).

Where
    Run on a management host. With ``--apply`` the tickets are posted to the GLPI
    REST API (tokens from ``GLPI_APP_TOKEN`` / ``GLPI_USER_TOKEN``). Default is a
    dry run that writes ``--out`` CSV and prints a summary.

Testable logic
    ``build_tickets`` and ``summarise`` are pure and deterministic, proven by
    ``scripts/tests/test_seed.py``.
"""

from __future__ import annotations

import argparse
import csv
import datetime as dt
import json
import logging
import os
import random
import sys
import urllib.request
from collections import Counter
from typing import Any

LOGGER = logging.getLogger("p09.seed")

SYNTHETIC_PREFIX = "[SYNTHETIC]"
DEFAULT_REQUESTERS = [
    "sara.khan", "omar.malik", "lena.hussain", "imran.sheikh", "hira.butt",
    "tariq.raza", "maya.qureshi", "zain.mirza", "aisha.chaudhry", "bilal.siddiqui",
    "noor.iqbal", "hamza.bhatti", "iqra.nawaz", "faisal.javed", "sana.aslam",
    "usman.rauf", "mina.anwar", "adil.gill", "rida.dar", "kamran.hashmi",
]
DEFAULT_TECHNICIANS = ["it.support.officer", "sysadmin"]
PRIORITY_MIX = [("P1", 2), ("P2", 12), ("P3", 45), ("P4", 41)]
STATUS_MIX = [("Closed", 82), ("Solved", 6), ("Processing (assigned)", 8), ("New", 4)]


def load_categories(catalogue_path: str) -> list[str]:
    """Return the flat list of ITIL category leaf names from the CMDB config."""
    with open(catalogue_path, encoding="utf-8") as handle:
        catalogue = json.load(handle)
    Leaves: list[str] = []
    for top in catalogue["itil_categories"]:
        Leaves.extend(top["children"])
    return Leaves


def _weighted_choice(rng: random.Random, pairs: list[tuple[str, int]]) -> str:
    population = [name for name, _ in pairs]
    weights = [weight for _, weight in pairs]
    return rng.choices(population, weights=weights, k=1)[0]


def _business_moment(rng: random.Random, day: dt.date) -> dt.datetime:
    """A random instant inside 08:00-18:00 on a weekday."""
    minute = rng.randint(8 * 60, 18 * 60 - 1)
    return dt.datetime.combine(day, dt.time(minute // 60, minute % 60))


def build_tickets(count: int, weeks: int, seed: int, categories: list[str],
                  requesters: list[str] | None = None,
                  technicians: list[str] | None = None,
                  end_date: dt.date | None = None) -> list[dict[str, Any]]:
    """Build a deterministic list of synthetic ticket dictionaries (pure)."""
    if count < 0:
        raise ValueError("count must be >= 0")
    if not categories:
        raise ValueError("at least one category is required")
    rng = random.Random(seed)
    requesters = requesters or DEFAULT_REQUESTERS
    technicians = technicians or DEFAULT_TECHNICIANS
    end_date = end_date or dt.date(2026, 10, 30)

    # Collect the business days that make up the simulated window.
    days: list[dt.date] = []
    cursor = end_date
    while len(days) < weeks * 5:
        if cursor.weekday() < 5:
            days.append(cursor)
        cursor -= dt.timedelta(days=1)
    days = list(reversed(days))

    tickets: list[dict[str, Any]] = []
    for index in range(count):
        day = rng.choice(days)
        created = _business_moment(rng, day)
        priority = _weighted_choice(rng, PRIORITY_MIX)
        status = _weighted_choice(rng, STATUS_MIX)
        category = rng.choice(categories)
        requester = rng.choice(requesters)
        technician = rng.choice(technicians)
        # Resolution times in business minutes; loosely tied to priority.
        base = {"P1": 180, "P2": 400, "P3": 900, "P4": 2000}[priority]
        if status in ("Closed", "Solved"):
            resolution = int(rng.gauss(base, base * 0.35))
            resolution = max(15, resolution)
        else:
            resolution = None
        tickets.append({
            "synthetic": True,
            "reference": f"SYN-{seed}-{index + 1:04d}",
            "subject": f"{SYNTHETIC_PREFIX} {category}: {_subject_for(category, rng)}",
            "category": category,
            "priority": priority,
            "requester": requester,
            "technician": technician,
            "status": status,
            "created": created.isoformat(sep=" "),
            "resolution_minutes": resolution,
        })
    return tickets


_SUBJECT_HINTS = {
    "Password reset / unlock": ["forgot password", "account locked out"],
    "New account": ["account for new starter"],
    "Group / folder access": ["access to the Finance share"],
    "MFA re-registration": ["new phone, need MFA reset"],
    "Laptop / desktop": ["laptop will not boot", "screen flickers"],
    "Printer": ["printer offline", "paper jam not clearing"],
    "Peripherals": ["docking station not detected"],
    "Warranty claim": ["keyboard key broken"],
    "Install request": ["please install the approved PDF tool"],
    "Fault / error": ["application crashes on open"],
    "Licence question": ["how many seats do we have"],
    "VPN access": ["VPN access for remote work"],
    "Connectivity": ["no network in meeting room"],
    "Wi-Fi": ["cannot join the office Wi-Fi"],
    "Mapped drives": ["department drive not mapped"],
    "Mailbox": ["mailbox full"],
    "Teams / SharePoint": ["cannot open the team site"],
    "Spam / phishing": ["suspicious email reported"],
    "Cannot print": ["nothing prints from Excel"],
    "Toner / consumables": ["toner low on floor 2"],
    "Print queue": ["jobs stuck in the queue"],
    "Report phishing": ["phishing email forwarded"],
    "Suspected incident": ["possible malware alert"],
    "Lost / stolen device": ["laptop left on a train"],
    "New starter": ["setup for Monday start"],
    "Leaver": ["last day today, offboard"],
    "Hardware quote": ["quote for two monitors"],
    "Change request": ["add a firewall rule"],
}


def _subject_for(category: str, rng: random.Random) -> str:
    hints = _SUBJECT_HINTS.get(category, ["support request"])
    return rng.choice(hints)


def summarise(tickets: list[dict[str, Any]]) -> dict[str, Any]:
    """Summarise a synthetic ticket set (pure; used for a dry-run preview)."""
    by_category = Counter(t["category"] for t in tickets)
    by_priority = Counter(t["priority"] for t in tickets)
    by_status = Counter(t["status"] for t in tickets)
    return {
        "total": len(tickets),
        "synthetic": True,
        "by_category": dict(by_category.most_common()),
        "by_priority": dict(by_priority),
        "by_status": dict(by_status),
    }


def write_csv(tickets: list[dict[str, Any]], path: str) -> None:
    if not tickets:
        LOGGER.warning("No tickets to write.")
        return
    with open(path, "w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(tickets[0].keys()))
        writer.writeheader()
        writer.writerows(tickets)
    LOGGER.info("Wrote %d synthetic tickets to %s", len(tickets), path)


def apply_to_glpi(tickets: list[dict[str, Any]], base_url: str, app_token: str, user_token: str) -> int:
    """POST tickets to GLPI (used only with --apply). Returns the count created."""
    base_url = base_url.rstrip("/")

    def request(method: str, path: str, body: Any | None = None, session: str | None = None) -> Any:
        headers = {"App-Token": app_token, "Content-Type": "application/json"}
        headers["Session-Token" if session else "Authorization"] = session or f"user_token {user_token}"
        data = json.dumps(body).encode() if body is not None else None
        req = urllib.request.Request(f"{base_url}/apirest.php/{path}", data=data, headers=headers, method=method)
        with urllib.request.urlopen(req, timeout=30) as response:  # noqa: S310 (lab-internal URL)
            payload = response.read().decode()
        return json.loads(payload) if payload else {}

    session = request("GET", "initSession").get("session_token")
    created = 0
    try:
        for ticket in tickets:
            request("POST", "Ticket", {"input": {
                "name": ticket["subject"],
                "content": f"Synthetic ticket generated for the P9 simulation. Requester: {ticket['requester']}.",
                "type": 1,
                "urgency": {"P1": 5, "P2": 4, "P3": 3, "P4": 2}[ticket["priority"]],
            }}, session=session)
            created += 1
    finally:
        request("GET", "killSession", session=session)
    return created


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description="Generate SYNTHETIC P9 service-desk tickets (dry run by default).")
    parser.add_argument("--count", type=int, default=150)
    parser.add_argument("--weeks", type=int, default=4)
    parser.add_argument("--seed", type=int, default=20261002)
    parser.add_argument("--catalogue", default=os.path.join(os.path.dirname(__file__), "..", "configs", "glpi-cmdb-categories.json"))
    parser.add_argument("--out", default=os.path.join(os.path.dirname(__file__), "..", "data", "halden-tickets.csv"))
    parser.add_argument("--glpi-url", default=os.environ.get("GLPI_URL", "https://glpi.halden.internal"))
    parser.add_argument("--apply", action="store_true", help="POST the tickets to GLPI (default is a dry run).")
    parser.add_argument("--log-level", default="INFO")
    args = parser.parse_args(argv)

    logging.basicConfig(level=args.log_level.upper(), format="%(asctime)s %(levelname)s %(message)s")
    categories = load_categories(args.catalogue)
    tickets = build_tickets(args.count, args.weeks, args.seed, categories)
    write_csv(tickets, args.out)
    LOGGER.info("Summary (synthetic): %s", json.dumps(summarise(tickets), indent=2))

    if not args.apply:
        LOGGER.info("Dry run complete. Every record is synthetic and prefixed %s.", SYNTHETIC_PREFIX)
        return 0

    app_token = os.environ.get("GLPI_APP_TOKEN")
    user_token = os.environ.get("GLPI_USER_TOKEN")
    if not (app_token and user_token):
        LOGGER.error("GLPI_APP_TOKEN and GLPI_USER_TOKEN must be set to apply.")
        return 2
    created = apply_to_glpi(tickets, args.glpi_url, app_token, user_token)
    LOGGER.info("Created %d SYNTHETIC tickets in GLPI.", created)
    return 0


if __name__ == "__main__":
    sys.exit(main())
