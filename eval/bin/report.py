#!/usr/bin/env python3
"""Render a self-contained HTML report for one eval run, plus the score
progression across every recorded run of the same case."""

import argparse
import html
import json
from pathlib import Path

# Categorical slots 1 and 2 from the validated default palette; the pair passes
# the lightness, chroma, CVD and contrast gates in both light and dark mode.
SERIES = {
    "with-skill": {"light": "#2a78d6", "dark": "#3987e5", "label": "With skill"},
    "no-skill":   {"light": "#eb6834", "dark": "#d95926", "label": "No skill"},
}
VARIANTS = ["no-skill", "with-skill"]


def model_key(row):
    """The model a history row measured. --model takes an alias that resolves to
    the newest release, so rows are keyed by what it resolved to; rows from
    before that was recorded are kept apart rather than guessed."""
    return row.get("model_id") or "%s (unrecorded)" % row.get("model", "?")


def variant_of(row):
    """Which side of the comparison a row belongs to.

    Recorded results predating the rename carry "arm"; they are historical
    records and are not rewritten, so both spellings are read here.
    """
    return row.get("variant") or row.get("arm") or "?"

CSS = """
:root { color-scheme: light; --surface-1:#fcfcfb; --plane:#f9f9f7; --ink:#0b0b0b;
  --ink-2:#52514e; --muted:#898781; --grid:#e1e0d9; --axis:#c3c2b7;
  --border:rgba(11,11,11,0.10); --s1:#2a78d6; --s2:#eb6834;
  --good:#0ca30c; --warning:#fab219; --critical:#d03b3b; }
@media (prefers-color-scheme: dark) {
  :root:not([data-theme="light"]) { color-scheme: dark; --surface-1:#1a1a19;
    --plane:#0d0d0d; --ink:#fff; --ink-2:#c3c2b7; --muted:#898781; --grid:#2c2c2a;
    --axis:#383835; --border:rgba(255,255,255,0.10); --s1:#3987e5; --s2:#d95926; }
}
:root[data-theme="dark"] { color-scheme: dark; --surface-1:#1a1a19; --plane:#0d0d0d;
  --ink:#fff; --ink-2:#c3c2b7; --muted:#898781; --grid:#2c2c2a; --axis:#383835;
  --border:rgba(255,255,255,0.10); --s1:#3987e5; --s2:#d95926; }
* { box-sizing:border-box; }
body { margin:0; padding:32px 24px 72px; background:var(--plane); color:var(--ink);
  font:15px/1.5 system-ui,-apple-system,"Segoe UI",sans-serif; }
.wrap { max-width:940px; margin:0 auto; }
h1 { font-size:22px; margin:0 0 4px; font-weight:600; }
h2 { font-size:15px; margin:0 0 14px; font-weight:600; letter-spacing:.01em; }
.sub { color:var(--ink-2); font-size:13px; margin:0 0 22px; }
.sub code { font-size:12px; background:var(--surface-1); padding:1px 5px;
  border:1px solid var(--border); border-radius:4px; }
.card { background:var(--surface-1); border:1px solid var(--border); border-radius:10px;
  padding:20px 22px; margin:0 0 20px; }
.tiles { display:flex; gap:14px; flex-wrap:wrap; margin:0 0 6px; }
.tile { flex:1 1 150px; background:var(--surface-1); border:1px solid var(--border);
  border-radius:10px; padding:14px 16px; }
.tile .k { font-size:12px; color:var(--ink-2); display:flex; align-items:center; gap:7px; }
.tile .v { font-size:30px; font-weight:600; letter-spacing:-.02em; margin-top:6px; }
.tile .m { font-size:12px; color:var(--muted); }
.swatch { width:9px; height:9px; border-radius:2px; display:inline-block; }
table { border-collapse:collapse; width:100%; font-size:13.5px; }
th, td { text-align:left; padding:8px 10px; border-bottom:1px solid var(--grid); vertical-align:top; }
th { font-weight:600; color:var(--ink-2); font-size:12px; text-transform:uppercase;
  letter-spacing:.04em; }
td.num, th.num { text-align:right; font-variant-numeric:tabular-nums; white-space:nowrap; }
tr:last-child td { border-bottom:none; }
.mark { font-weight:600; margin-right:5px; }
.badge { font-size:13px; font-weight:600; letter-spacing:.02em; margin-left:4px; }
.pass { color:var(--good); } .part { color:var(--warning); } .fail { color:var(--critical); }
.detail { color:var(--muted); font-size:12px; }
.legend { display:flex; gap:18px; font-size:12.5px; color:var(--ink-2); margin:0 0 10px; }
.legend span { display:flex; align-items:center; gap:7px; }
details { margin-top:12px; }
summary { cursor:pointer; font-size:13px; color:var(--ink-2); padding:4px 0; }
pre { background:var(--plane); border:1px solid var(--border); border-radius:8px;
  padding:12px 14px; overflow:auto; font-size:12px; line-height:1.45; max-height:420px; }
.note { font-size:12.5px; color:var(--muted); }
#tt { position:fixed; pointer-events:none; opacity:0; transition:opacity .08s;
  background:var(--surface-1); border:1px solid var(--border); border-radius:8px;
  padding:8px 10px; font-size:12px; box-shadow:0 4px 14px rgba(0,0,0,.14); z-index:9; }
#tt b { font-weight:600; } #tt div { display:flex; align-items:center; gap:7px; margin-top:4px; }
.toggle { position:fixed; top:14px; right:16px; font-size:12px; color:var(--ink-2);
  background:var(--surface-1); border:1px solid var(--border); border-radius:999px;
  padding:5px 12px; cursor:pointer; }
"""

JS = """
const t = document.getElementById('tt');
document.querySelectorAll('svg[data-chart]').forEach(svg => {
  const pts = JSON.parse(svg.dataset.points);
  const cross = svg.querySelector('.crosshair');
  svg.addEventListener('mousemove', ev => {
    const r = svg.getBoundingClientRect();
    const x = (ev.clientX - r.left) / r.width * svg.viewBox.baseVal.width;
    let best = null;
    pts.forEach(p => { if (!best || Math.abs(p.x - x) < Math.abs(best.x - x)) best = p; });
    if (!best) return;
    cross.setAttribute('x1', best.x); cross.setAttribute('x2', best.x);
    cross.style.opacity = 1;
    t.innerHTML = '<b>' + best.label + '</b>' + best.rows;
    t.style.opacity = 1;
    t.style.left = Math.min(ev.clientX + 14, window.innerWidth - 220) + 'px';
    t.style.top = (ev.clientY - 12) + 'px';
  });
  svg.addEventListener('mouseleave', () => {
    t.style.opacity = 0; cross.style.opacity = 0;
  });
});
const btn = document.querySelector('.toggle');
btn.addEventListener('click', () => {
  const dark = document.documentElement.dataset.theme === 'dark';
  document.documentElement.dataset.theme = dark ? 'light' : 'dark';
});
"""


def e(s):
    return html.escape(str(s), quote=True)


def mark(earned, weight):
    if weight and earned >= weight - 1e-9:
        return '<span class="mark pass">PASS</span>'
    if earned > 0:
        return '<span class="mark part">PARTIAL</span>'
    return '<span class="mark fail">FAIL</span>'


def chart(case, series, labels, maxscore):
    """Line chart of score per run. Two series, legend, direct end labels,
    crosshair tooltip, and a table-view twin rendered by the caller."""
    W, H = 900, 300
    ml, mr, mt, mb = 46, 92, 18, 40
    pw, ph = W - ml - mr, H - mt - mb
    n = len(labels)
    step = pw / max(n - 1, 1)

    def X(i):
        return ml + (i * step if n > 1 else pw / 2)

    def Y(v):
        return mt + ph - (v / maxscore) * ph

    out = []
    for gy in (0, 25, 50, 75, 100):
        v = maxscore * gy / 100
        y = Y(v)
        out.append('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="var(--grid)" stroke-width="1"/>'
                   % (ml, y, ml + pw, y))
        out.append('<text x="%d" y="%.1f" text-anchor="end" font-size="11" fill="var(--muted)" '
                   'style="font-variant-numeric:tabular-nums">%d</text>' % (ml - 8, y + 4, round(v)))
    out.append('<line x1="%d" y1="%.1f" x2="%d" y2="%.1f" stroke="var(--axis)" stroke-width="1"/>'
               % (ml, Y(0), ml + pw, Y(0)))
    out.append('<line class="crosshair" x1="0" y1="%d" x2="0" y2="%d" stroke="var(--axis)" '
               'stroke-width="1" style="opacity:0"/>' % (mt, mt + ph))

    every = max(1, n // 8)
    for i, lab in enumerate(labels):
        if i % every == 0 or i == n - 1:
            out.append('<text x="%.1f" y="%d" text-anchor="middle" font-size="10.5" '
                       'fill="var(--muted)" style="font-variant-numeric:tabular-nums">%s</text>'
                       % (X(i), mt + ph + 20, e(lab)))

    for variant in VARIANTS:
        vals = series.get(variant)
        if not vals:
            continue
        col = "var(--s1)" if variant == "with-skill" else "var(--s2)"
        pts = [(X(i), Y(v)) for i, v in enumerate(vals) if v is not None]
        if len(pts) > 1:
            out.append('<polyline fill="none" stroke="%s" stroke-width="2" stroke-linejoin="round" '
                       'stroke-linecap="round" points="%s"/>'
                       % (col, " ".join("%.1f,%.1f" % p for p in pts)))
        for x, y in pts:
            out.append('<circle cx="%.1f" cy="%.1f" r="4" fill="%s" stroke="var(--surface-1)" '
                       'stroke-width="2"/>' % (x, y, col))
        if pts:
            # Label the last point drawn, not vals[-1]: a --variant run leaves
            # the other series None at the newest position.
            x, y = pts[-1]
            last = [v for v in vals if v is not None][-1]
            out.append('<text x="%.1f" y="%.1f" font-size="12" font-weight="600" fill="%s">%s %.0f</text>'
                       % (x + 10, y + 4, col, e(SERIES[variant]["label"]), last))

    hover = []
    for i, lab in enumerate(labels):
        rows = ""
        for variant in VARIANTS:
            v = (series.get(variant) or [None] * n)[i]
            if v is None:
                continue
            col = "var(--s1)" if variant == "with-skill" else "var(--s2)"
            rows += ('<div><span class="swatch" style="background:%s"></span>%s <b>%.1f</b></div>'
                     % (col, SERIES[variant]["label"], v))
        hover.append({"x": round(X(i), 1), "label": lab, "rows": rows})

    return ('<svg data-chart="%s" viewBox="0 0 %d %d" width="100%%" role="img" '
            'aria-label="Score per eval run for %s" data-points=\'%s\'>%s</svg>'
            % (e(case), W, H, e(case), html.escape(json.dumps(hover), quote=False),
               "".join(out)))


def functional_tile(variant, fn):
    """Headline tile for the dry-run proof. A policy can score low on the
    conformance checks and still honour augments, so this is reported beside the
    score rather than buried in the per-run detail."""
    ov, tot = fn.get("overridden") or 0, fn.get("total") or 0
    status = fn.get("status")
    if status == "ok":
        cls, badge, val = "pass", "PROVEN", "%d/%d" % (ov, tot)
        detail = "every tunable took the injected value"
    elif status == "partial":
        cls, badge, val = "part", "PARTIAL", "%d/%d" % (ov, tot)
        detail = "%d of %d tunables took the injected value" % (ov, tot)
    elif status == "no override observed":
        cls, badge, val = "fail", "NO EFFECT", "0/%d" % tot
        detail = "the injected def.json changed nothing"
    elif status == "no tunables":
        cls, badge, val = "part", "NOT TESTED", "n/a"
        detail = "no <code>def.</code> tunables to inject &mdash; may still work another way"
    elif status == "mixed":
        cls, badge, val = "part", "MIXED", "%.1f/%.1f" % (ov, tot)
        detail = "runs disagreed: " + ", ".join(fn.get("statuses") or [])
    else:
        cls, badge, val = "detail", "NOT RUN", "n/a"
        detail = e(status or "pass --functional to measure this")
    col = "var(--s1)" if variant == "with-skill" else "var(--s2)"
    # An unmeasured result is muted: the badge carries the status, so the number
    # slot must not shout in a status colour it has not earned.
    vstyle = ' style="color:var(--muted)"' if val == "n/a" else ""
    return ('<div class="tile"><div class="k"><span class="swatch" style="background:%s"></span>'
            'Augments override &middot; %s</div>'
            '<div class="v %s"%s>%s <span class="badge %s">%s</span></div>'
            '<div class="m">%s</div></div>'
            % (col, e(SERIES[variant]["label"]), "" if vstyle else cls, vstyle, val, cls, badge, detail))


def legend():
    return ('<div class="legend">'
            + "".join('<span><span class="swatch" style="background:%s"></span>%s</span>'
                      % ("var(--s1)" if a == "with-skill" else "var(--s2)", SERIES[a]["label"])
                      for a in VARIANTS)
            + "</div>")


def variant_detail(run_dir, case, variant):
    parts = []
    for d in sorted((run_dir / case / variant).glob("run*")):
        rf = d / "result.json"
        if not rf.exists():
            continue
        r = json.loads(rf.read_text())
        v = r["validation"]
        lines = []
        for key, label in (("standalone", "cf-promises (standalone)"), ("stdlib", "cf-promises (+ stdlib.cf)")):
            for item in v.get(key) or []:
                lines.append("%s  %s  rc=%d%s\n%s" % (
                    label, item["file"], item["rc"],
                    "  [bundlesequence: %s]" % item["bundlesequence"] if item.get("bundlesequence") else "",
                    item["output"] or "(clean)"))
        cli = r.get("cli") or {}
        meta = "turns=%s  duration=%.1fs  cost=$%.4f  policy_source=%s" % (
            cli.get("num_turns", "?"), (cli.get("duration_ms") or 0) / 1000.0,
            cli.get("total_cost_usd") or 0.0, r["artifacts"]["sources"]["policy"])
        policy = ""
        for name in r["artifacts"]["policy_files"]:
            for p in list((d / "workdir").rglob(name)) + list((d / "extracted").glob(name)):
                policy += "----- %s -----\n%s\n" % (name, p.read_text(errors="replace"))
                break
        for name in r["artifacts"]["augments_files"]:
            for p in list((d / "workdir").rglob(name)) + list((d / "extracted").glob(name)):
                policy += "----- %s -----\n%s\n" % (name, p.read_text(errors="replace"))
                break
        fn = r.get("functional")
        fn_txt = ""
        if fn and fn.get("ran"):
            fn_txt = "\nfunctional augments override: %s  (overridden: %s / not: %s)" % (
                fn["status"], ", ".join(fn["overridden"]) or "-", ", ".join(fn["not_overridden"]) or "-")
        parts.append(
            "<details><summary>%s run%02d &mdash; score %.1f/%d</summary>"
            "<pre>%s\n\n%s%s</pre><details><summary>generated policy</summary><pre>%s</pre></details>"
            "</details>"
            % (e(SERIES[variant]["label"]), r.get("run", 1), r["score"], r["max_score"],
               e(meta), e("\n\n".join(lines)), e(fn_txt), e(policy or "(none captured)")))
    return "".join(parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--history", required=True)
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    run_dir = Path(args.run_dir)
    summary = json.loads((run_dir / "summary.json").read_text())
    info = summary.get("info", {})
    skill = info.get("skill", {})

    hist = []
    hp = Path(args.history)
    if hp.exists():
        for line in hp.read_text().splitlines():
            if line.strip():
                try:
                    hist.append(json.loads(line))
                except ValueError:
                    pass

    body = []
    body.append('<h1>cfengine-policy skill eval</h1>')
    harness = info.get("harness", {})
    # The alias passed to --model, and what it resolved to in this run.
    ids = sorted({model_key(h) for h in hist if h["run_id"] == run_dir.name})
    model_txt = e(info.get("model", "?")) + (" &rarr; " + ", ".join(e(i) for i in ids) if ids else "")
    body.append('<p class="sub">%s &middot; model <code>%s</code> &middot; skill <code>%s</code>%s '
                '&middot; %s</p>'
                % (e(info.get("timestamp", run_dir.name)), model_txt,
                   e(skill.get("id", "?")),
                   ' &middot; <span class="fail">uncommitted edits</span>' if skill.get("dirty") else "",
                   e(info.get("cfengine", ""))))
    body.append('<p class="sub">harness <code>%s</code> &middot; eval <code>%s</code>%s '
                '&middot; skill commit <code>%s</code></p>'
                % (e(harness.get("claude_code", "unknown")),
                   e(harness.get("eval_commit", "unknown")[:12]),
                   ' &middot; <span class="fail">uncommitted eval edits</span>'
                   if harness.get("eval_dirty") else "",
                   e(skill.get("commit", "")[:12])))

    for case, variants in sorted(summary["cases"].items()):
        title = case
        cf = run_dir.parent.parent / "cases" / case / "case.json"
        if cf.exists():
            title = json.loads(cf.read_text()).get("title", case)
        body.append('<div class="card"><h2>%s <span class="detail">(%s)</span></h2>' % (e(title), e(case)))

        tiles = []
        for variant in VARIANTS:
            a = variants.get(variant)
            if not a:
                continue
            col = "var(--s1)" if variant == "with-skill" else "var(--s2)"
            spread = "" if a["runs"] < 2 else " &middot; %.0f&ndash;%.0f" % (a["score_min"], a["score_max"])
            tiles.append('<div class="tile"><div class="k"><span class="swatch" style="background:%s">'
                         '</span>%s</div><div class="v">%.0f<span class="m">/%d</span></div>'
                         '<div class="m">%d run%s%s</div></div>'
                         % (col, SERIES[variant]["label"], a["score_mean"], a["max_score"],
                            a["runs"], "" if a["runs"] == 1 else "s", spread))
        if "delta" in variants:
            d = variants["delta"]
            cls = "pass" if d > 0 else ("fail" if d < 0 else "detail")
            tiles.append('<div class="tile"><div class="k">Skill delta</div>'
                         '<div class="v %s">%+.0f</div><div class="m">points attributable '
                         'to the skill</div></div>' % (cls, d))
        body.append('<div class="tiles">%s</div>' % "".join(tiles))

        ftiles = [functional_tile(a, variants[a]["functional"]) for a in VARIANTS
                  if variants.get(a) and variants[a].get("functional")]
        if ftiles:
            body.append('<div class="tiles" style="margin-top:14px">%s</div>' % "".join(ftiles))

        ref = variants.get("with-skill") or variants.get("no-skill")
        rows = []
        for cid, c in ref["checks"].items():
            cells = ""
            for variant in VARIANTS:
                a = variants.get(variant)
                if not a:
                    continue
                ch = a["checks"].get(cid, {"earned_mean": 0})
                cells += '<td class="num">%s%.1f</td>' % (mark(ch["earned_mean"], c["weight"]), ch["earned_mean"])
            rows.append("<tr><td>%s</td><td class=\"num detail\">%d</td>%s</tr>"
                        % (e(c["label"]), c["weight"], cells))
        heads = "".join('<th class="num">%s</th>' % e(SERIES[a]["label"]) for a in VARIANTS if a in variants)
        body.append('<table><thead><tr><th>Check</th><th class="num">Weight</th>%s</tr></thead>'
                    '<tbody>%s</tbody></table>' % (heads, "".join(rows)))

        this = {model_key(h) for h in hist if h["run_id"] == run_dir.name and h["case"] == case}
        rel = [h for h in hist if h["case"] == case and model_key(h) in this]
        runs = sorted({h["run_id"] for h in rel})
        labels = [r[4:6] + "-" + r[6:8] + " " + r[9:13] for r in runs]
        series = {}
        for variant in VARIANTS:
            vals = []
            for rid in runs:
                m = [h for h in rel if h["run_id"] == rid and variant_of(h) == variant]
                vals.append(m[0]["score_mean"] if m else None)
            if any(v is not None for v in vals):
                series[variant] = vals
        body.append('<h2 style="margin-top:26px">Progression</h2>')
        if len(runs) >= 2:
            body.append(legend())
            body.append(chart(case, series, labels, ref["max_score"]))
        else:
            body.append('<p class="note">A trend line appears once this case has been run twice. '
                        'The table below is the full record.</p>')
        trows = []
        for i, rid in enumerate(runs):
            sid = next((h["skill_id"] for h in rel if h["run_id"] == rid), "?")
            cells = ""
            for variant in VARIANTS:
                v = (series.get(variant) or [None] * len(runs))[i]
                cells += '<td class="num">%s</td>' % ("&mdash;" if v is None else "%.1f" % v)
            d = ""
            if series.get("with-skill") and series.get("no-skill"):
                a, b = series["with-skill"][i], series["no-skill"][i]
                d = "%+.1f" % (a - b) if a is not None and b is not None else "&mdash;"
            trows.append('<tr><td style="font-variant-numeric:tabular-nums">%s</td>'
                         '<td class="detail"><code>%s</code></td>%s<td class="num">%s</td></tr>'
                         % (e(rid), e(sid), cells, d))
        body.append('<details open><summary>Table view &mdash; every recorded run of this case</summary>'
                    '<table><thead><tr><th>Run</th><th>Skill revision</th>%s<th class="num">Delta</th>'
                    '</tr></thead><tbody>%s</tbody></table></details>'
                    % ("".join('<th class="num">%s</th>' % e(SERIES[a]["label"]) for a in VARIANTS),
                       "".join(trows)))

        body.append('<h2 style="margin-top:26px">This run</h2>')
        for variant in VARIANTS:
            if variant in variants:
                body.append(variant_detail(run_dir, case, variant))
        body.append("</div>")

    doc = ("<!doctype html><html lang=\"en\"><head><meta charset=\"utf-8\">"
           "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">"
           "<title>cfengine-policy eval %s</title><style>%s</style></head><body>"
           "<button class=\"toggle\">light / dark</button><div id=\"tt\"></div>"
           "<div class=\"wrap\">%s</div><script>%s</script></body></html>"
           % (e(run_dir.name), CSS, "".join(body), JS))
    Path(args.out).write_text(doc)
    print("report: %s" % args.out)


if __name__ == "__main__":
    main()
