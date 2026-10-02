#!/usr/bin/env python3
"""prioritize.py — risk-based vulnerability prioritisation for the Halden P5 lab.

The problem this solves: a raw scanner report is a list of everything that is wrong, not a plan.
A small team cannot fix every "critical" finding, and CVSS alone is a poor guide because most
high-CVSS CVEs are never exploited. This tool turns a scanner export into a short, ranked
remediation work list by enriching each finding with:

* **CISA KEV status** — is this vulnerability known to be exploited in the wild?
* **FIRST EPSS** — what is the estimated probability it will be exploited in the next 30 days?
* **Exposure** — is the asset internet-facing or internal?
* **Asset criticality** — how much does the business depend on this host?

It then assigns a P0–P4 tier, a remediation SLA date and a 0–100 priority score, and reports the
tier distribution (the "funnel": many findings in, few urgent actions out).

Design notes
------------
* **Standard library only.** No third-party packages, so the tool runs on a fresh Ubuntu host and
  its tests are reproducible offline. The KEV/EPSS feeds are read from a local cache by default;
  ``fetch-feeds`` is the only subcommand that reaches the network, and it only downloads two public
  data files (it never scans anything).
* **Pure scoring core.** ``tier()``, ``sla_days()`` and ``priority_score()`` take primitive
  arguments and return values — no I/O, no globals — which is why the unit tests in
  ``tests/test_prioritize.py`` can pin every boundary of the model.
* **Dry run first.** ``--dry-run`` computes and logs the work list but writes nothing to disk.
* **Lab only.** This tool never contacts a target host; it reads a scan export. The scanner that
  produces that export is scoped to the Halden lab ranges (AGENTS.md rule R1), enforced by
  ``scripts/lib/labguard.sh`` and ``scripts/02-setup-targets.sh``.

Subcommands
-----------
  run          ingest -> enrich -> tier -> write the work list (CSV and JSON)
  summary      print the tier distribution and SLA snapshot without writing files
  explain      show the full scoring breakdown for one CVE (optionally on one host)
  fetch-feeds  download and cache the CISA KEV catalogue and FIRST EPSS scores

Example
-------
  python3 scripts/05-prioritize.py run \\
      --findings data/sample-scanner-export.csv \\
      --assets   data/asset-criticality.csv \\
      --enrichment data/sample-enrichment.json \\
      --rules    configs/p05-tier-rules.yml \\
      --as-of    2026-10-02 \\
      --out-csv  reports/prioritized-work-list.csv \\
      --json-bundle demo/sample-findings.json \\
      --js-bundle   demo/sample-findings.js
"""
from __future__ import annotations

import argparse
import csv
import json
import logging
import sys
import urllib.request
from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta
from pathlib import Path
from typing import Any, Iterable, Iterator, Mapping, Sequence

LOG = logging.getLogger("p05.prioritize")

TIERS: tuple[str, ...] = ("P0", "P1", "P2", "P3", "P4")
KEV_URL = "https://www.cisa.gov/sites/default/files/feeds/known_exploited_vulnerabilities.json"
EPSS_URL = "https://api.first.org/data/v1/epss"


# --------------------------------------------------------------------------------------
# Rules: the model's tuning knobs. Kept in a frozen dataclass so a rule set cannot be
# mutated halfway through a run (that would make two findings non-comparable).
# --------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Rules:
    """Thresholds, SLA targets and score weights for the prioritisation model."""

    epss_critical: float = 0.5
    epss_high: float = 0.1
    cvss_critical: float = 9.0
    cvss_high: float = 7.0
    sla_days: Mapping[str, int] = field(
        default_factory=lambda: {"P0": 3, "P1": 7, "P2": 30, "P3": 60, "P4": 180}
    )
    weights: Mapping[str, float] = field(
        default_factory=lambda: {
            "kev": 40.0,
            "epss": 25.0,
            "exposure": 15.0,
            "cvss": 12.0,
            "criticality": 8.0,
            "ransomware_bonus": 5.0,
        }
    )


DEFAULT_RULES = Rules()


# --------------------------------------------------------------------------------------
# Input records
# --------------------------------------------------------------------------------------
@dataclass(frozen=True)
class Finding:
    """One row from the scanner export (already JSON-decoded, not yet enriched)."""

    host: str
    cve: str
    cvss: float
    service: str
    port: int
    title: str
    solution: str
    first_seen: date


@dataclass(frozen=True)
class Asset:
    """One row from the asset-criticality inventory."""

    host: str
    role: str
    exposure: str  # "internet" or "internal"
    criticality: int  # 1 low, 2 medium, 3 high
    owner: str


@dataclass(frozen=True)
class Enrichment:
    """KEV + EPSS values for a CVE (empty for findings with no CVE)."""

    in_kev: bool = False
    ransomware: bool = False
    epss: float = 0.0


@dataclass(frozen=True)
class WorkItem:
    """A deduplicated, enriched, tiered finding ready to work."""

    tier: str
    sla_days: int
    due: date
    overdue: bool
    priority_score: float
    host: str
    asset_role: str
    owner: str
    exposure: str
    criticality: int
    cve: str
    cvss: float
    epss: float
    in_kev: bool
    ransomware: bool
    service: str
    port: int
    title: str
    solution: str
    first_seen: date
    reasons: str


# --------------------------------------------------------------------------------------
# Pure scoring core
# --------------------------------------------------------------------------------------
def _clamp(value: float, low: float, high: float) -> float:
    """Return ``value`` limited to the inclusive range ``[low, high]``."""
    return max(low, min(high, value))


def tier(
    in_kev: bool,
    exposed: bool,
    epss: float,
    cvss: float,
    criticality: int,
    rules: Rules = DEFAULT_RULES,
) -> str:
    """Return the remediation tier (``P0``–``P4``) for one finding.

    Pure: no file access, no network, no global state — the same inputs always give the same
    output, which is what makes it unit-testable and auditable. The rule order is the model:
    first match wins, so a known-exploited internet-facing finding is P0 even if its CVSS is
    only moderate.

    Args:
        in_kev: the CVE appears in the CISA Known Exploited Vulnerabilities catalogue.
        exposed: the asset is internet-facing (or terminates the WAN/VPN).
        epss: FIRST EPSS probability, 0.0–1.0.
        cvss: CVSS base score, 0.0–10.0.
        criticality: asset criticality, 1 (low) to 3 (high).
        rules: thresholds to apply (defaults mirror ``configs/p05-tier-rules.yml``).
    """
    if in_kev and exposed:
        return "P0"
    if in_kev or (exposed and epss >= rules.epss_critical):
        return "P1"
    if epss >= rules.epss_high or (cvss >= rules.cvss_critical and criticality >= 3):
        return "P2"
    if cvss >= rules.cvss_high:
        return "P3"
    return "P4"


def sla_days(tier_name: str, rules: Rules = DEFAULT_RULES) -> int:
    """Return the remediation SLA target, in days, for a tier."""
    return int(rules.sla_days[tier_name])


def priority_score(
    in_kev: bool,
    ransomware: bool,
    exposed: bool,
    epss: float,
    cvss: float,
    criticality: int,
    rules: Rules = DEFAULT_RULES,
) -> float:
    """Return a 0–100 score used to rank findings *inside* a tier (never to pick the tier)."""
    weights = rules.weights
    score = 0.0
    if in_kev:
        score += float(weights["kev"])
    score += float(weights["epss"]) * _clamp(epss, 0.0, 1.0)
    if exposed:
        score += float(weights["exposure"])
    score += float(weights["cvss"]) * _clamp(cvss, 0.0, 10.0) / 10.0
    score += float(weights["criticality"]) * (_clamp(criticality, 1, 3) - 1) / 2.0
    if ransomware:
        score += float(weights["ransomware_bonus"])
    return round(min(100.0, score), 1)


def explain_reasons(
    in_kev: bool,
    ransomware: bool,
    exposed: bool,
    epss: float,
    cvss: float,
    criticality: int,
    rules: Rules = DEFAULT_RULES,
) -> list[str]:
    """Return human-readable reasons why a finding scored the way it did."""
    reasons: list[str] = []
    if in_kev:
        reasons.append("listed in CISA KEV (known exploited)")
    if ransomware:
        reasons.append("KEV entry linked to a known ransomware campaign")
    if exposed:
        reasons.append("internet-facing asset")
    if epss >= rules.epss_high:
        reasons.append(f"EPSS {epss:.2f} (elevated exploit probability)")
    if cvss >= rules.cvss_high:
        reasons.append(f"CVSS {cvss:.1f}")
    if criticality >= 3:
        reasons.append("business-critical asset (criticality 3)")
    return reasons or ["no elevated signal; batched into the routine update cycle"]


# --------------------------------------------------------------------------------------
# I/O helpers — tolerant of comment lines and blank lines in the lab's config-style CSVs
# --------------------------------------------------------------------------------------
def _iter_data_rows(path: Path) -> Iterator[dict[str, str]]:
    """Yield CSV rows, skipping blank lines and lines beginning with ``#``."""
    with path.open(newline="", encoding="utf-8") as handle:
        filtered = (line for line in handle if line.strip() and not line.lstrip().startswith("#"))
        reader = csv.DictReader(filtered)
        if reader.fieldnames is None:
            raise ValueError(f"{path}: no header row found")
        for raw in reader:
            yield {str(k).strip(): (v or "").strip() for k, v in raw.items() if k is not None}


def _to_float(value: str | None, default: float = 0.0) -> float:
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return default


def _to_int(value: str | None, default: int = 0) -> int:
    try:
        return int(float(str(value).strip()))
    except (TypeError, ValueError):
        return default


def _to_date(value: str | None, default: date | None = None) -> date:
    text = str(value or "").strip()
    if text:
        try:
            return datetime.strptime(text, "%Y-%m-%d").date()
        except ValueError:
            LOG.warning("unparseable date %r; using %s", text, default or "today")
    return default or date.today()


def load_findings(path: Path) -> list[Finding]:
    """Load a scanner export CSV into :class:`Finding` records."""
    findings: list[Finding] = []
    for row in _iter_data_rows(path):
        findings.append(
            Finding(
                host=row.get("host", "").lower(),
                cve=(row.get("cve", "") or "").upper(),
                cvss=_to_float(row.get("cvss")),
                service=row.get("service", ""),
                port=_to_int(row.get("port")),
                title=row.get("title", ""),
                solution=row.get("solution", ""),
                first_seen=_to_date(row.get("first_seen")),
            )
        )
    return findings


def load_assets(path: Path) -> dict[str, Asset]:
    """Load the asset-criticality inventory CSV, keyed by lowercase host name."""
    assets: dict[str, Asset] = {}
    for row in _iter_data_rows(path):
        host = row.get("host", "").lower()
        if not host:
            continue
        assets[host] = Asset(
            host=host,
            role=row.get("role", ""),
            exposure=(row.get("exposure", "") or "internal").lower(),
            criticality=_to_int(row.get("criticality"), 1),
            owner=row.get("owner", ""),
        )
    return assets


def load_enrichment(path: Path) -> dict[str, Enrichment]:
    """Load a cached KEV+EPSS bundle keyed by CVE id.

    The accepted shape is ``{"cves": {"CVE-...": {"kev": true, "ransomware": false, "epss": 0.9}}}``
    so one small file describes both feeds and the tool stays offline by default.
    """
    document = json.loads(Path(path).read_text(encoding="utf-8"))
    table = document.get("cves", document) if isinstance(document, dict) else {}
    enrichment: dict[str, Enrichment] = {}
    for cve, values in table.items():
        if not isinstance(values, dict):
            continue
        enrichment[cve.upper()] = Enrichment(
            in_kev=bool(values.get("kev", values.get("in_kev", False))),
            ransomware=bool(values.get("ransomware", False)),
            epss=_to_float(str(values.get("epss", 0.0))),
        )
    return enrichment


def _load_yaml_like(path: Path) -> dict[str, Any]:
    """Load a YAML or JSON config into a plain dict (YAML only if PyYAML is installed)."""
    text = path.read_text(encoding="utf-8")
    if "yaml" in sys.modules:
        return dict(sys.modules["yaml"].safe_load(text) or {})
    try:
        import yaml  # type: ignore[import-not-found]
    except ModuleNotFoundError:
        try:
            return dict(json.loads(text))
        except json.JSONDecodeError as exc:  # pragma: no cover - defensive
            raise SystemExit(
                f"{path}: it looks like YAML but PyYAML is not installed. "
                "Install PyYAML or pass a JSON config."
            ) from exc
    return dict(yaml.safe_load(text) or {})


def rules_from_mapping(mapping: Mapping[str, Any], base: Rules = DEFAULT_RULES) -> Rules:
    """Overlay thresholds/weights from a config mapping onto a base :class:`Rules`."""
    thresholds = mapping.get("thresholds", {}) or {}
    sla = {**base.sla_days, **{str(k): int(v) for k, v in (mapping.get("sla_days", {}) or {}).items()}}
    weights = dict(base.weights)
    for key, value in (mapping.get("scoring_weights", mapping.get("weights", {})) or {}).items():
        weights[str(key)] = float(value)
    return Rules(
        epss_critical=float(thresholds.get("epss_critical", base.epss_critical)),
        epss_high=float(thresholds.get("epss_high", base.epss_high)),
        cvss_critical=float(thresholds.get("cvss_critical", base.cvss_critical)),
        cvss_high=float(thresholds.get("cvss_high", base.cvss_high)),
        sla_days=sla,
        weights=weights,
    )


# --------------------------------------------------------------------------------------
# Pipeline
# --------------------------------------------------------------------------------------
def deduplicate(findings: Sequence[Finding]) -> tuple[list[Finding], int]:
    """Remove exact duplicates a scanner may report more than once.

    The key is ``(host, CVE-or-title, service, port)``: the same CVE found by two checks on the
    same host and port is one remediation task, not two. Returns the kept findings and the number
    of rows removed.
    """
    seen: set[tuple[str, str, str, int]] = set()
    kept: list[Finding] = []
    for finding in findings:
        key = (finding.host, finding.cve or finding.title.lower(), finding.service.lower(), finding.port)
        if key in seen:
            continue
        seen.add(key)
        kept.append(finding)
    return kept, len(findings) - len(kept)


def classify(
    finding: Finding,
    asset: Asset | None,
    enrichment: Enrichment,
    rules: Rules = DEFAULT_RULES,
    as_of: date | None = None,
) -> WorkItem:
    """Enrich a single finding and return a fully tiered :class:`WorkItem`."""
    reference = as_of or date.today()
    exposure = asset.exposure if asset else "internal"
    criticality = asset.criticality if asset else 1
    exposed = exposure == "internet"
    tier_name = tier(enrichment.in_kev, exposed, enrichment.epss, finding.cvss, criticality, rules)
    days = sla_days(tier_name, rules)
    due = finding.first_seen + timedelta(days=days)
    return WorkItem(
        tier=tier_name,
        sla_days=days,
        due=due,
        overdue=due < reference,
        priority_score=priority_score(
            enrichment.in_kev, enrichment.ransomware, exposed, enrichment.epss, finding.cvss, criticality, rules
        ),
        host=finding.host,
        asset_role=asset.role if asset else "unknown asset",
        owner=asset.owner if asset else "IT",
        exposure=exposure,
        criticality=criticality,
        cve=finding.cve,
        cvss=finding.cvss,
        epss=enrichment.epss,
        in_kev=enrichment.in_kev,
        ransomware=enrichment.ransomware,
        service=finding.service,
        port=finding.port,
        title=finding.title,
        solution=finding.solution,
        first_seen=finding.first_seen,
        reasons="; ".join(
            explain_reasons(
                enrichment.in_kev, enrichment.ransomware, exposed, enrichment.epss, finding.cvss, criticality, rules
            )
        ),
    )


def build_work_list(
    findings: Sequence[Finding],
    assets: Mapping[str, Asset],
    enrichment: Mapping[str, Enrichment],
    rules: Rules = DEFAULT_RULES,
    as_of: date | None = None,
) -> tuple[list[WorkItem], dict[str, Any]]:
    """Run the whole pipeline and return the ranked work list plus a summary dict.

    Ranking: tier first (P0 before P4), then priority score, then CVSS — so the top of the list is
    the work a small team should pick up on Monday morning.
    """
    reference = as_of or date.today()
    deduped, removed = deduplicate(findings)
    items = [
        classify(finding, assets.get(finding.host), enrichment.get(finding.cve, Enrichment()), rules, reference)
        for finding in deduped
    ]
    items.sort(key=lambda item: (TIERS.index(item.tier), -item.priority_score, -item.cvss, item.host))

    tier_counts = {name: 0 for name in TIERS}
    overdue = {name: 0 for name in TIERS}
    for item in items:
        tier_counts[item.tier] += 1
        if item.overdue:
            overdue[item.tier] += 1
    p0p1 = tier_counts["P0"] + tier_counts["P1"]
    summary: dict[str, Any] = {
        "as_of": reference.isoformat(),
        "findings_raw": len(findings),
        "findings_deduplicated": len(deduped),
        "duplicates_removed": removed,
        "findings_with_cve": sum(1 for item in items if item.cve),
        "findings_in_kev": sum(1 for item in items if item.in_kev),
        "findings_on_exposed_assets": sum(1 for item in items if item.exposure == "internet"),
        "tier_counts": tier_counts,
        "p0_p1_count": p0p1,
        "p0_p1_pct": round(100.0 * p0p1 / len(items), 1) if items else 0.0,
        "overdue_by_tier": overdue,
        # MTTR is intentionally absent: it needs two scans (finding seen, then closed) and there has
        # been no scan yet. AGENTS.md rule R2 — do not invent it.
        "mttr": "not measured",
        "sample_data_note": (
            "Synthetic sample input. The counts describe the bundled sample dataset, "
            "not a real scan of any network."
        ),
    }
    return items, summary


# --------------------------------------------------------------------------------------
# Output
# --------------------------------------------------------------------------------------
_WORK_LIST_FIELDS = (
    "tier",
    "sla_days",
    "due",
    "overdue",
    "priority_score",
    "host",
    "asset_role",
    "owner",
    "exposure",
    "criticality",
    "cve",
    "cvss",
    "epss",
    "in_kev",
    "ransomware",
    "service",
    "port",
    "title",
    "solution",
    "first_seen",
    "reasons",
)


def work_item_to_row(item: WorkItem) -> dict[str, Any]:
    """Flatten a :class:`WorkItem` into a JSON/CSV-friendly dict of primitives."""
    row = asdict(item)
    for key in ("due", "first_seen"):
        row[key] = row[key].isoformat()
    return row


def write_csv(items: Sequence[WorkItem], path: Path) -> None:
    """Write the work list to CSV with a stable column order."""
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(_WORK_LIST_FIELDS))
        writer.writeheader()
        for item in items:
            writer.writerow(work_item_to_row(item))
    LOG.info("wrote %d rows to %s", len(items), path)


def write_json(items: Sequence[WorkItem], summary: Mapping[str, Any], path: Path) -> None:
    """Write the work list plus summary to JSON."""
    path.parent.mkdir(parents=True, exist_ok=True)
    document = {
        "schema": "p05-prioritizer-worklist/1",
        "synthetic_data": True,
        "summary": dict(summary),
        "items": [work_item_to_row(item) for item in items],
    }
    path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    LOG.info("wrote JSON work list to %s", path)


def build_browser_bundle(
    findings: Sequence[Finding],
    assets: Mapping[str, Asset],
    enrichment: Mapping[str, Enrichment],
    rules: Rules,
    summary: Mapping[str, Any],
    as_of: date,
) -> dict[str, Any]:
    """Build the static demo bundle: raw inputs plus the rules, so the browser can re-score."""
    deduped, _ = deduplicate(findings)
    bundled_findings = []
    for finding in deduped:
        values = enrichment.get(finding.cve, Enrichment())
        bundled_findings.append(
            {
                "host": finding.host,
                "cve": finding.cve,
                "cvss": finding.cvss,
                "service": finding.service,
                "port": finding.port,
                "title": finding.title,
                "solution": finding.solution,
                "first_seen": finding.first_seen.isoformat(),
                "in_kev": values.in_kev,
                "ransomware": values.ransomware,
                "epss": values.epss,
            }
        )
    return {
        "schema": "p05-prioritizer-bundle/1",
        "generated_by": "projects/p05-vuln-management/scripts/05-prioritize.py",
        "synthetic_data": True,
        "lab_only": True,
        "as_of": as_of.isoformat(),
        "rules": {
            "thresholds": {
                "epss_critical": rules.epss_critical,
                "epss_high": rules.epss_high,
                "cvss_critical": rules.cvss_critical,
                "cvss_high": rules.cvss_high,
            },
            "sla_days": dict(rules.sla_days),
            "weights": dict(rules.weights),
        },
        "assets": [asdict(asset) for asset in assets.values()],
        "findings": bundled_findings,
        "python_summary": dict(summary),
    }


# --------------------------------------------------------------------------------------
# Feed fetching (the only network-touching code path; it downloads public data, never scans)
# --------------------------------------------------------------------------------------
def fetch_feeds(out: Path) -> None:
    """Download the CISA KEV catalogue and FIRST EPSS scores into one cache file."""
    LOG.info("downloading CISA KEV catalogue ...")
    with urllib.request.urlopen(KEV_URL, timeout=60) as response:  # noqa: S310 - fixed public URL
        kev = json.loads(response.read().decode("utf-8"))
    kev_cves = {str(item.get("cveID", "")).upper(): item for item in kev.get("vulnerabilities", [])}

    cves = sorted(kev_cves)
    epss: dict[str, float] = {}
    LOG.info("downloading EPSS scores for %d CVEs (batched) ...", len(cves))
    for start in range(0, len(cves), 100):
        batch = ",".join(cves[start : start + 100])
        url = f"{EPSS_URL}?cve={batch}"
        with urllib.request.urlopen(url, timeout=60) as response:  # noqa: S310 - fixed public URL
            data = json.loads(response.read().decode("utf-8"))
        for entry in data.get("data", []):
            epss[str(entry.get("cve", "")).upper()] = float(entry.get("epss", 0.0))

    document = {
        "fetched_at": datetime.utcnow().isoformat(timespec="seconds") + "Z",
        "source": {"kev": KEV_URL, "epss": EPSS_URL},
        "cves": {
            cve: {
                "kev": True,
                "ransomware": kev_cves.get(cve, {}).get("knownRansomwareCampaignUse") == "Known",
                "epss": epss.get(cve, 0.0),
            }
            for cve in cves
        },
    }
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
    LOG.info("cached %d CVEs to %s", len(document["cves"]), out)


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------
def _add_input_args(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--findings", type=Path, help="scanner export CSV")
    parser.add_argument("--assets", type=Path, help="asset-criticality inventory CSV")
    parser.add_argument("--enrichment", type=Path, help="cached KEV+EPSS JSON")
    parser.add_argument("--rules", type=Path, help="tier rules YAML/JSON")
    parser.add_argument("--as-of", type=date.fromisoformat, help="reference date (YYYY-MM-DD)")


def _resolve_inputs(args: argparse.Namespace) -> tuple[Path, Path, Path, Rules, date]:
    """Resolve inputs from CLI flags and/or a config file, applying built-in defaults."""
    config: dict[str, Any] = {}
    if getattr(args, "config", None):
        config = _load_yaml_like(args.config)

    def pick(flag: str, config_key: str, default: Any) -> Any:
        value = getattr(args, flag, None)
        if value is not None:
            return value
        return config.get(config_key, default)

    findings = _required_path(pick("findings", "findings", None), "findings")
    assets = _required_path(pick("assets", "assets", None), "assets")
    enrichment = Path(pick("enrichment", "enrichment", "data/sample-enrichment.json"))
    if not enrichment.exists():
        LOG.warning("enrichment file %s not found; treating every finding as not-KEV / EPSS 0", enrichment)

    rules = DEFAULT_RULES
    rules_path = pick("rules", "rules", None)
    if rules_path:
        candidate = Path(rules_path)
        if candidate.exists():
            rules = rules_from_mapping(_load_yaml_like(candidate))
        else:
            LOG.warning("rules file %s not found; using built-in defaults", candidate)

    as_of = pick("as_of", "as_of", None)
    if isinstance(as_of, str):
        as_of = date.fromisoformat(as_of)
    reference = as_of if isinstance(as_of, date) else date.today()
    return findings, assets, enrichment, rules, reference


def _required_path(value: Any, name: str) -> Path:
    if not value:
        raise SystemExit(f"--{name} is required (or set it in --config)")
    path = Path(value)
    if not path.exists():
        raise SystemExit(f"{name} file not found: {path}")
    return path


def _load_enrichment_safe(path: Path) -> dict[str, Enrichment]:
    if str(path) == "/dev/null" or not path.exists():
        return {}
    return load_enrichment(path)


def _print_summary(summary: Mapping[str, Any]) -> None:
    counts = summary["tier_counts"]
    LOG.info(
        "findings %d -> deduplicated %d (removed %d) -> P0 %d, P1 %d, P2 %d, P3 %d, P4 %d",
        summary["findings_raw"],
        summary["findings_deduplicated"],
        summary["duplicates_removed"],
        counts["P0"],
        counts["P1"],
        counts["P2"],
        counts["P3"],
        counts["P4"],
    )
    LOG.info(
        "urgent queue P0+P1 = %d of %d (%.1f%%); KEV findings %d",
        summary["p0_p1_count"],
        summary["findings_deduplicated"],
        summary["p0_p1_pct"],
        summary["findings_in_kev"],
    )


def _cmd_run(args: argparse.Namespace) -> int:
    findings_path, assets_path, enrichment_path, rules, reference = _resolve_inputs(args)
    findings = load_findings(findings_path)
    assets = load_assets(assets_path)
    enrichment = _load_enrichment_safe(enrichment_path)
    items, summary = build_work_list(findings, assets, enrichment, rules, reference)
    _print_summary(summary)
    if args.dry_run:
        LOG.info("dry run: computed %d work items; nothing written", len(items))
        return 0
    if args.out_csv:
        write_csv(items, args.out_csv)
    if args.out_json:
        write_json(items, summary, args.out_json)
    if args.json_bundle:
        bundle = build_browser_bundle(findings, assets, enrichment, rules, summary, reference)
        args.json_bundle.parent.mkdir(parents=True, exist_ok=True)
        args.json_bundle.write_text(json.dumps(bundle, indent=2) + "\n", encoding="utf-8")
        LOG.info("wrote browser bundle to %s", args.json_bundle)
        if args.js_bundle:
            args.js_bundle.write_text(
                "// Auto-generated by scripts/05-prioritize.py. SYNTHETIC sample data — do not edit.\n"
                "window.P05_DATA = " + json.dumps(bundle) + ";\n",
                encoding="utf-8",
            )
            LOG.info("wrote browser bundle wrapper to %s", args.js_bundle)
    return 0


def _cmd_summary(args: argparse.Namespace) -> int:
    findings_path, assets_path, enrichment_path, rules, reference = _resolve_inputs(args)
    items, summary = build_work_list(
        load_findings(findings_path), load_assets(assets_path), _load_enrichment_safe(enrichment_path), rules, reference
    )
    _print_summary(summary)
    print(json.dumps(summary, indent=2))
    return 0


def _cmd_explain(args: argparse.Namespace) -> int:
    findings_path, assets_path, enrichment_path, rules, reference = _resolve_inputs(args)
    findings = load_findings(findings_path)
    assets = load_assets(assets_path)
    enrichment = _load_enrichment_safe(enrichment_path)
    wanted = args.cve.upper()
    deduped, _ = deduplicate(findings)
    matches = [f for f in deduped if f.cve.upper() == wanted and (not args.host or f.host == args.host.lower())]
    if not matches:
        raise SystemExit(f"no finding for {wanted}" + (f" on {args.host}" if args.host else ""))
    for finding in matches:
        item = classify(finding, assets.get(finding.host), enrichment.get(finding.cve, Enrichment()), rules, reference)
        print(f"{item.host:8s} {item.cve or '(no CVE)':16s} tier={item.tier} score={item.priority_score}")
        print(f"  cvss={item.cvss} epss={item.epss} kev={item.in_kev} exposed={item.exposure == 'internet'}"
              f" criticality={item.criticality}")
        print(f"  due={item.due} (sla {item.sla_days}d, overdue={item.overdue})")
        print(f"  why: {item.reasons}")
        print(f"  fix: {item.solution}")
    return 0


def _cmd_fetch_feeds(args: argparse.Namespace) -> int:
    fetch_feeds(args.out)
    return 0


def build_parser() -> argparse.ArgumentParser:
    """Build the ``argparse`` command-line parser."""
    parser = argparse.ArgumentParser(
        prog="prioritize.py", description="Risk-based vulnerability prioritisation (Halden P5 lab)."
    )
    parser.add_argument("--log-level", default="INFO", help="logging level (DEBUG, INFO, WARNING, ERROR)")
    sub = parser.add_subparsers(dest="command", required=True)

    run = sub.add_parser("run", help="compute and write the prioritised work list")
    _add_input_args(run)
    run.add_argument("--config", type=Path, help="prioritizer.yml run configuration")
    run.add_argument("--out-csv", type=Path, help="write the work list as CSV")
    run.add_argument("--out-json", type=Path, help="write the work list as JSON")
    run.add_argument("--json-bundle", type=Path, help="write the static demo bundle JSON")
    run.add_argument("--js-bundle", type=Path, help="write the demo bundle as a browser-loadable .js")
    run.add_argument("--dry-run", action="store_true", help="compute only; write nothing")
    run.set_defaults(func=_cmd_run)

    summary = sub.add_parser("summary", help="print the tier distribution without writing files")
    _add_input_args(summary)
    summary.add_argument("--config", type=Path, help="prioritizer.yml run configuration")
    summary.set_defaults(func=_cmd_summary)

    explain = sub.add_parser("explain", help="show the scoring breakdown for one CVE")
    _add_input_args(explain)
    explain.add_argument("--config", type=Path, help="prioritizer.yml run configuration")
    explain.add_argument("--cve", required=True, help="CVE id to explain, e.g. CVE-2021-44228")
    explain.add_argument("--host", help="limit to one host")
    explain.set_defaults(func=_cmd_explain)

    feeds = sub.add_parser("fetch-feeds", help="download and cache the CISA KEV and FIRST EPSS feeds")
    feeds.add_argument("--out", type=Path, default=Path("data/kev-epss-cache.json"), help="cache file to write")
    feeds.set_defaults(func=_cmd_fetch_feeds)
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    """Entry point: parse arguments, configure logging, dispatch the subcommand."""
    parser = build_parser()
    args = parser.parse_args(argv)
    logging.basicConfig(
        level=getattr(logging, str(args.log_level).upper(), logging.INFO),
        format="%(asctime)s %(levelname)-7s %(name)s: %(message)s",
        datefmt="%Y-%m-%d %H:%M:%S",
    )
    return int(args.func(args))


if __name__ == "__main__":
    raise SystemExit(main())
