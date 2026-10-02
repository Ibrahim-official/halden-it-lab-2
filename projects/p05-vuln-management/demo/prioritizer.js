/*!
 * prioritizer.js — a dependency-free, browser re-implementation of the P5 prioritisation model.
 *
 * This is the same rule order, thresholds, SLA targets and score weights that
 * scripts/05-prioritize.py implements (see docs/00-design.md §3 and configs/p05-tier-rules.yml).
 * It exists so the tier model can be demonstrated interactively over the bundled *synthetic*
 * sample data without a server, a build step or a network connection.
 *
 * It is deliberately small: the production logic lives in Python and is unit-tested there. This
 * file only mirrors it for the demo, and the banner in index.html says so.
 *
 * DATA IS SYNTHETIC. See the "Synthetic data" banner in demo/index.html.
 */
(function () {
  'use strict';

  /** Return the tier for one finding. First match wins — same order as the Python tier(). */
  function tier(finding, asset, rules) {
    var exposed = asset && asset.exposure === 'internet';
    var criticality = asset ? asset.criticality : 1;
    if (finding.in_kev && exposed) return 'P0';
    if (finding.in_kev || (exposed && finding.epss >= rules.thresholds.epss_critical)) return 'P1';
    if (finding.epss >= rules.thresholds.epss_high ||
        (finding.cvss >= rules.thresholds.cvss_critical && criticality >= 3)) return 'P2';
    if (finding.cvss >= rules.thresholds.cvss_high) return 'P3';
    return 'P4';
  }

  /** 0-100 score used to rank findings inside a tier; never used to pick the tier. */
  function score(finding, asset, rules) {
    var exposed = asset && asset.exposure === 'internet';
    var criticality = asset ? asset.criticality : 1;
    var w = rules.weights;
    var total = 0;
    if (finding.in_kev) total += w.kev;
    total += w.epss * Math.max(0, Math.min(1, finding.epss));
    if (exposed) total += w.exposure;
    total += w.cvss * Math.max(0, Math.min(10, finding.cvss)) / 10;
    total += w.criticality * (Math.max(1, Math.min(3, criticality)) - 1) / 2;
    if (finding.ransomware) total += w.ransomware_bonus;
    return Math.round(Math.min(100, total) * 10) / 10;
  }

  /** Human-readable reasons for the decision, shown in the table. */
  function reasons(finding, asset, rules) {
    var exposed = asset && asset.exposure === 'internet';
    var out = [];
    if (finding.in_kev) out.push('listed in CISA KEV');
    if (finding.ransomware) out.push('known ransomware campaign');
    if (exposed) out.push('internet-facing asset');
    if (finding.epss >= rules.thresholds.epss_high) out.push('EPSS ' + finding.epss.toFixed(2));
    if (finding.cvss >= rules.thresholds.cvss_high) out.push('CVSS ' + finding.cvss.toFixed(1));
    if (asset && asset.criticality >= 3) out.push('business-critical asset');
    return out.length ? out.join('; ') : 'no elevated signal; routine cycle';
  }

  /** Add SLA due date and overdue flag, mirroring the Python WorkItem. */
  function enrich(finding, asset, rules, asOf) {
    var t = tier(finding, asset, rules);
    var days = rules.sla_days[t];
    var firstSeen = new Date(finding.first_seen + 'T00:00:00Z');
    var due = new Date(firstSeen.getTime() + days * 86400000);
    var reference = new Date(asOf + 'T00:00:00Z');
    return {
      tier: t,
      sla_days: days,
      due: due.toISOString().slice(0, 10),
      overdue: due < reference,
      priority_score: score(finding, asset, rules),
      reasons: reasons(finding, asset, rules),
      finding: finding,
      asset: asset || { role: 'unknown asset', exposure: 'internal', criticality: 1, owner: 'IT' }
    };
  }

  /** Run the whole model over a bundle and return the ranked work list plus a summary. */
  function run(bundle) {
    var assetsByHost = {};
    bundle.assets.forEach(function (a) { assetsByHost[a.host] = a; });
    var order = { P0: 0, P1: 1, P2: 2, P3: 3, P4: 4 };
    var items = bundle.findings.map(function (f) {
      return enrich(f, assetsByHost[f.host], bundle.rules, bundle.as_of);
    });
    items.sort(function (a, b) {
      if (order[a.tier] !== order[b.tier]) return order[a.tier] - order[b.tier];
      if (b.priority_score !== a.priority_score) return b.priority_score - a.priority_score;
      return b.finding.cvss - a.finding.cvss;
    });
    var counts = { P0: 0, P1: 0, P2: 0, P3: 0, P4: 0 };
    var overdue = { P0: 0, P1: 0, P2: 0, P3: 0, P4: 0 };
    items.forEach(function (i) {
      counts[i.tier]++;
      if (i.overdue) overdue[i.tier]++;
    });
    return {
      items: items,
      counts: counts,
      overdue: overdue,
      total: items.length,
      urgent: counts.P0 + counts.P1,
      urgentPct: items.length ? Math.round(1000 * (counts.P0 + counts.P1) / items.length) / 10 : 0,
      kev: items.filter(function (i) { return i.finding.in_kev; }).length
    };
  }

  window.P05_MODEL = { tier: tier, score: score, reasons: reasons, enrich: enrich, run: run };
}());
