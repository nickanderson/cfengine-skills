#!/usr/bin/env python3
"""Cross-model comparison from history.jsonl.

The per-run report charts one model's progression. This charts every model
side by side for a single case: a dumbbell per model, no-skill to with-skill,
because "before -> after per item" is what the skill delta actually is. The
connector length IS the delta.
"""

import argparse
import html
import json
from pathlib import Path

from report import CSS, SERIES, VARIANTS, e, variant_of  # one source of truth for the palette

JS = """
const t = document.getElementById('tt');
document.querySelectorAll('[data-row]').forEach(el => {
  el.addEventListener('mousemove', ev => {
    t.innerHTML = el.dataset.row;
    t.style.opacity = 1;
    t.style.left = Math.min(ev.clientX + 14, window.innerWidth - 240) + 'px';
    t.style.top = (ev.clientY - 12) + 'px';
  });
  el.addEventListener('mouseleave', () => { t.style.opacity = 0; });
});
const btn = document.querySelector('.toggle');
btn.addEventListener('click', () => {
  const dark = document.documentElement.dataset.theme === 'dark';
  document.documentElement.dataset.theme = dark ? 'light' : 'dark';
});
"""


def load_all(history):
    rows = []
    for line in Path(history).read_text().splitlines():
        if line.strip():
            try:
                rows.append(json.loads(line))
            except ValueError:
                continue
    return rows


def load(rows_all, case):
    rows = [r for r in rows_all if r.get("case") == case]
    latest = {}
    for r in rows:
        m = r["model"]
        if m not in latest or r["run_id"] > latest[m]:
            latest[m] = r["run_id"]
    models = {}
    for r in rows:
        if r["run_id"] == latest[r["model"]]:
            models.setdefault(r["model"], {})[variant_of(r)] = r
    return models, latest


def functional_of(results_dir, run_id, case, variant):
    f = Path(results_dir) / run_id / "summary.json"
    if not f.exists():
        return None
    try:
        return json.loads(f.read_text())["cases"][case][variant].get("functional")
    except (ValueError, KeyError, OSError):
        return None


def fn_label(fn):
    if not fn:
        return "not run", "detail"
    s = fn.get("status")
    ov, tot = fn.get("overridden") or 0, fn.get("total") or 0
    if s == "ok":
        return "proven %g/%g" % (ov, tot), "pass"
    if s == "partial":
        return "partial %g/%g" % (ov, tot), "part"
    if s == "no override observed":
        return "no effect", "fail"
    if s == "no tunables":
        return "not tested", "part"
    if s == "mixed":
        short = {"ok": "proven", "partial": "partial", "no override observed": "no effect",
                 "no tunables": "not tested"}
        counts = fn.get("counts") or {}
        parts = ["%d %s" % (n, short.get(k, k)) for k, n in
                 sorted(counts.items(), key=lambda kv: -kv[1])]
        worst = ("fail" if "no override observed" in counts
                 else "part" if ("partial" in counts or "no tunables" in counts) else "pass")
        return ", ".join(parts), worst
    return e(s or "not run"), "detail"


def dumbbell(models, order, maxscore):
    W = 900
    ml, mr, mt, rowh = 118, 96, 26, 58
    pw = W - ml - mr
    H = mt + rowh * len(order) + 34

    def X(v):
        return ml + (v / maxscore) * pw

    out = []
    for gv in (0, 25, 50, 75, 100):
        v = maxscore * gv / 100
        out.append('<line x1="%.1f" y1="%d" x2="%.1f" y2="%d" stroke="var(--grid)" '
                   'stroke-width="1"/>' % (X(v), mt - 10, X(v), mt + rowh * len(order) - 18))
        out.append('<text x="%.1f" y="%d" text-anchor="middle" font-size="11" fill="var(--muted)" '
                   'style="font-variant-numeric:tabular-nums">%d</text>'
                   % (X(v), mt + rowh * len(order) + 6, round(v)))

    for i, m in enumerate(order):
        y = mt + rowh * i + 8
        variants = models[m]
        out.append('<text x="%d" y="%.1f" text-anchor="end" font-size="13" fill="var(--ink)" '
                   'font-weight="600">%s</text>' % (ml - 14, y + 5, e(m)))
        pts = {}
        for variant in VARIANTS:
            r = variants.get(variant)
            if r:
                pts[variant] = r["score_mean"]
        if len(pts) == 2:
            out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="var(--axis)" '
                       'stroke-width="2" stroke-linecap="round"/>'
                       % (X(pts["no-skill"]), y, X(pts["with-skill"]), y))
        for variant in VARIANTS:
            r = variants.get(variant)
            if not r:
                continue
            col = "var(--s1)" if variant == "with-skill" else "var(--s2)"
            lo, hi = r["score_min"], r["score_max"]
            if hi > lo:
                out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
                           'stroke-width="1.5" stroke-linecap="round" opacity="0.45"/>'
                           % (X(lo), y, X(hi), y, col))
            out.append('<circle cx="%.1f" cy="%.1f" r="5" fill="%s" stroke="var(--surface-1)" '
                       'stroke-width="2"/>' % (X(r["score_mean"]), y, col))
        if len(pts) == 2:
            d = pts["with-skill"] - pts["no-skill"]
            cls = "var(--good)" if d > 0 else ("var(--critical)" if d < 0 else "var(--muted)")
            out.append('<text x="%d" y="%.1f" font-size="13" font-weight="600" fill="%s" '
                       'style="font-variant-numeric:tabular-nums">%+.0f</text>'
                       % (ml + pw + 14, y + 5, cls, d))
        tip = "<b>%s</b>" % e(m)
        for variant in VARIANTS:
            r = variants.get(variant)
            if not r:
                continue
            col = "var(--s1)" if variant == "with-skill" else "var(--s2)"
            tip += ('<div><span class="swatch" style="background:%s"></span>%s <b>%.1f</b> '
                    '(%g&ndash;%g, n=%d)</div>'
                    % (col, SERIES[variant]["label"], r["score_mean"],
                       r["score_min"], r["score_max"], r["runs"]))
        out.append('<rect data-row=\'%s\' x="%d" y="%.1f" width="%d" height="%d" fill="transparent" '
                   'style="cursor:crosshair"/>'
                   % (html.escape(tip, quote=True), ml - 110, y - rowh / 2 + 4, pw + 206, rowh))
    return ('<svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="Score by model, '
            'no skill versus with skill">%s</svg>' % (W, H, "".join(out)))


def render_case(rows_all, results_dir, case):
    models, latest = load(rows_all, case)
    if not models:
        return ""
    order = sorted(models, key=lambda m: -(models[m].get("with-skill", {}).get("score_mean", 0)))
    maxscore = next(iter(next(iter(models.values())).values()))["max_score"]

    body = []
    body.append('<div class="card"><h2>%s</h2>' % e(case))
    body.append('<div class="legend">'
                + "".join('<span><span class="swatch" style="background:%s"></span>%s</span>'
                          % ("var(--s1)" if a == "with-skill" else "var(--s2)", SERIES[a]["label"])
                          for a in VARIANTS) + '</div>')
    body.append(dumbbell(models, order, maxscore))

    rows = []
    for m in order:
        variants = models[m]
        cells = ""
        for variant in VARIANTS:
            r = variants.get(variant)
            if not r:
                cells += '<td class="num">&mdash;</td><td class="num detail">&mdash;</td>'
                continue
            spread = "&mdash;" if r["runs"] < 2 else "%g&ndash;%g" % (r["score_min"], r["score_max"])
            cells += ('<td class="num">%.1f</td><td class="num detail">%s</td>' % (r["score_mean"], spread))
        d = ""
        if len(variants) == 2:
            v = variants["with-skill"]["score_mean"] - variants["no-skill"]["score_mean"]
            d = '<span class="%s">%+.1f</span>' % ("pass" if v > 0 else "fail" if v < 0 else "detail", v)
        fl, fc = fn_label(functional_of(results_dir, latest[m], case, "with-skill"))
        n = max((variants[a]["runs"] for a in variants), default=0)
        rows.append('<tr><td><b>%s</b></td><td class="num detail">%d</td>%s<td class="num">%s</td>'
                    '<td class="%s">%s</td><td class="detail"><code>%s</code></td></tr>'
                    % (e(m), n, cells, d, fc, fl, e(latest[m])))
    body.append('<details open><summary>Table view &mdash; mean, run range, and the functional '
                'proof for the with-skill variant</summary><table><thead><tr>'
                '<th>Model</th><th class="num">n</th>'
                '<th class="num">No skill</th><th class="num">range</th>'
                '<th class="num">With skill</th><th class="num">range</th>'
                '<th class="num">Delta</th><th>Augments override</th><th>Run</th>'
                '</tr></thead><tbody>%s</tbody></table></details>' % "".join(rows))
    body.append('<p class="note" style="margin-top:14px">Delta measures adherence to the pattern '
                'the skill teaches. A model can score low and still emit working policy &mdash; read '
                'the augments-override column as the functional ground truth.</p>')
    body.append('</div>')
    return "".join(body)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--history", required=True)
    ap.add_argument("--results-dir", required=True)
    ap.add_argument("--case", action="append",
                    help="case id (repeatable); default: every case in the history")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    rows_all = load_all(args.history)
    cases = args.case or sorted({r["case"] for r in rows_all if "case" in r})
    if not cases:
        raise SystemExit("compare: no cases found in %s" % args.history)

    body = ['<h1>cfengine-policy skill &mdash; model comparison</h1>',
            '<p class="sub">latest run per model &middot; dot = mean, rule = run range, '
            'connector = skill delta</p>']
    rendered = 0
    for case in cases:
        html_case = render_case(rows_all, args.results_dir, case)
        if html_case:
            body.append(html_case)
            rendered += 1
    if not rendered:
        raise SystemExit("compare: no history rows for %s" % ", ".join(cases))

    doc = ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
           '<meta name="viewport" content="width=device-width,initial-scale=1">'
           '<title>cfengine-policy model comparison</title><style>%s</style></head><body>'
           '<button class="toggle">light / dark</button><div id="tt"></div>'
           '<div class="wrap">%s</div><script>%s</script></body></html>'
           % (CSS, "".join(body), JS))
    Path(args.out).write_text(doc)
    print("compare: %s" % args.out)


if __name__ == "__main__":
    main()
