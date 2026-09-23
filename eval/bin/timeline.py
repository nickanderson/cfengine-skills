#!/usr/bin/env python3
"""Full-history view across every recorded run, including archived ones.

compare.py shows the latest run per model; this shows the whole arc. Runs are
NOT all comparable -- the rubric and the validation engine have both changed --
so the timeline bands each "ruler regime" and refuses to draw a connecting line
across a boundary. Within a band the trend is real; across one it is not.
"""

import argparse
import html
import json
from pathlib import Path

from report import CSS, SERIES, VARIANTS, e, model_key, variant_of

JS = """
const t = document.getElementById('tt');
document.querySelectorAll('[data-row]').forEach(el => {
  el.addEventListener('mousemove', ev => {
    t.innerHTML = el.dataset.row; t.style.opacity = 1;
    t.style.left = Math.min(ev.clientX + 14, window.innerWidth - 260) + 'px';
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


def load(history_paths, case):
    rows, info_by_run = [], {}
    for hp in history_paths:
        hp = Path(hp)
        if not hp.exists():
            continue
        base = hp.parent
        for line in hp.read_text().splitlines():
            if not line.strip():
                continue
            try:
                r = json.loads(line)
            except ValueError:
                continue
            if r.get("case") != case:
                continue
            r["_base"] = str(base)
            rows.append(r)
            rid = r["run_id"]
            if rid not in info_by_run:
                f = base / rid / "run-info.json"
                try:
                    info_by_run[rid] = json.loads(f.read_text())
                except (OSError, ValueError):
                    info_by_run[rid] = {}
    return rows, info_by_run


def ruler_of(info, rv=None):
    """What the score is measured with. A change here re-bases the numbers."""
    engine = info.get("engine")
    if not engine:
        engine = "host" if info.get("host") or info.get("cfengine") else "unknown"
    engine = engine.split()[0]
    rv = rv if rv is not None else info.get("rubric_version")
    # How the skill reached the model. Runs before this key existed handed over a
    # raw SKILL.md with --add-dir, so its dynamic blocks never ran and the model
    # never got the documentation paths -- a different thing to measure, not a
    # better score on the same thing.
    delivery = info.get("skill_delivery", "add-dir")
    return (rv if rv is not None else "?", engine, delivery)


def ruler_label(key):
    rv, engine, delivery = key
    return "rubric v%s &middot; %s &middot; skill %s" % (rv, e(engine), e(delivery))


def facets(runs, info_by_run, by_run_variant, models, maxscore, rubrics):
    """One row per model, each on its OWN run sequence.

    A shared x axis across models looks tidy but is unreadable here: a model
    that ran twice out of seven runs is five-sevenths empty, nothing is
    adjacent so no line is ever drawn, and the eye starts joining dots across
    facets. Each facet therefore plots only its own runs, side by side.
    """
    W = 920
    ml, mr, mt, fh, lab, gap = 46, 108, 40, 96, 20, 44
    pw = W - ml - mr
    rowh = fh + lab
    H = mt + len(models) * (rowh + gap)

    out = []
    for row_i, m in enumerate(models):
        top = mt + row_i * (rowh + gap)
        mine = [r for r in runs if any((r, m, a) in by_run_variant for a in VARIANTS)]
        n = len(mine)
        # cap the spacing: with two runs, full-width spacing implies a gap in
        # time that is not there -- they are simply consecutive
        step = min(pw / max(n - 1, 1), 150)

        def X(i, n=n, step=step):
            return ml + (i * step if n > 1 else pw / 2)

        def Y(v, top=top):
            return top + fh - (v / maxscore) * fh

        keys = [rubrics.get(r, 1) for r in mine]
        engines = [ruler_of(info_by_run.get(r, {}), rubrics.get(r)) for r in mine]

        band = 0
        st = 0
        for i in range(1, n + 1):
            if i == n or engines[i] != engines[st]:
                x0 = X(st) - step / 2 if n > 1 else ml
                x1 = X(i - 1) + step / 2 if n > 1 else ml + pw
                x0, x1 = max(x0, ml - 12), min(x1, ml + pw + 12)
                x1 = min(x1, X(n - 1) + step / 2 + 10)
                if band % 2:
                    out.append('<rect x="%.1f" y="%d" width="%.1f" height="%d" fill="var(--ink)" '
                               'opacity="0.035"/>' % (x0, top - 12, x1 - x0, fh + 16))
                out.append('<text x="%.1f" y="%d" text-anchor="middle" font-size="10" '
                           'fill="var(--muted)">%s</text>'
                           % ((x0 + x1) / 2, top - 17, ruler_label(engines[st])))
                band += 1
                st = i

        out.append('<text x="%d" y="%.1f" font-size="12.5" font-weight="600" '
                   'fill="var(--ink)">%s</text>' % (ml, top - 30, e(m)))
        # stop the plot where the data stops: full-width rules imply a chart
        # that continues, when this model simply has not run that many times
        xmax = min(ml + pw, max(X(n - 1) + step / 2 + 10, ml + 140))
        for gv in (0, 50, 100):
            y = Y(maxscore * gv / 100)
            out.append('<line x1="%d" y1="%.1f" x2="%.1f" y2="%.1f" stroke="var(--grid)" '
                       'stroke-width="1"/>' % (ml, y, xmax, y))
            out.append('<text x="%d" y="%.1f" text-anchor="end" font-size="9.5" '
                       'fill="var(--muted)">%d</text>' % (ml - 5, y + 3, round(maxscore * gv / 100)))

        for variant in VARIANTS:
            col = "var(--s1)" if variant == "with-skill" else "var(--s2)"
            seg = []
            for i, rid in enumerate(mine):
                row = by_run_variant.get((rid, m, variant))
                if row is None:
                    if seg:
                        out.append(_poly(seg, col))
                    seg = []
                    continue
                if seg and engines[i] != engines[i - 1]:
                    out.append(_poly(seg, col))
                    seg = []
                seg.append((X(i), Y(row["score_mean"])))
            if seg:
                out.append(_poly(seg, col))

            for i, rid in enumerate(mine):
                row = by_run_variant.get((rid, m, variant))
                if row is None:
                    continue
                x = X(i)
                # spread is within-run variance across repetitions, not movement
                # between runs -- drawn recessive so it cannot be read as a trend
                if row["score_max"] > row["score_min"]:
                    out.append('<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" '
                               'stroke-width="5" stroke-linecap="round" opacity="0.16"/>'
                               % (x, Y(row["score_min"]), x, Y(row["score_max"]), col))
                out.append('<circle cx="%.1f" cy="%.1f" r="4" fill="%s" stroke="var(--surface-1)" '
                           'stroke-width="2"/>' % (x, Y(row["score_mean"]), col))

        for i, rid in enumerate(mine):
            out.append('<text x="%.1f" y="%d" text-anchor="middle" font-size="9.5" '
                       'fill="var(--muted)" style="font-variant-numeric:tabular-nums">%s</text>'
                       % (X(i), top + fh + 15, e(rid[4:6] + "-" + rid[6:8] + " " + rid[9:13])))
            tip = "<b>%s &middot; %s</b>" % (e(m), e(rid))
            tip += '<div>%s</div>' % ruler_label(engines[i])
            for variant in VARIANTS:
                row = by_run_variant.get((rid, m, variant))
                if row is None:
                    continue
                col = "var(--s1)" if variant == "with-skill" else "var(--s2)"
                tip += ('<div><span class="swatch" style="background:%s"></span>%s <b>%.1f</b> '
                        '(%g&ndash;%g over %d runs)</div>'
                        % (col, SERIES[variant]["label"], row["score_mean"],
                           row["score_min"], row["score_max"], row["runs"]))
            out.append('<rect data-row=\'%s\' x="%.1f" y="%d" width="%.1f" height="%d" '
                       'fill="transparent" style="cursor:crosshair"/>'
                       % (html.escape(tip, quote=True), X(i) - step / 2, top - 12,
                          max(step, 14), fh + 24))

    return ('<svg viewBox="0 0 %d %d" width="100%%" role="img" aria-label="Score per run, '
            'per model">%s</svg>' % (W, H, "".join(out)))


def _poly(seg, col):
    if len(seg) < 2:
        return ""
    return ('<polyline fill="none" stroke="%s" stroke-width="2" stroke-linejoin="round" '
            'stroke-linecap="round" points="%s"/>'
            % (col, " ".join("%.1f,%.1f" % (p[0], p[1]) for p in seg)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--history", action="append", required=True,
                    help="history.jsonl (repeatable; archived ones too)")
    ap.add_argument("--case", default="01-motd")
    ap.add_argument("--out", required=True)
    args = ap.parse_args()

    rows, info_by_run = load(args.history, args.case)
    if not rows:
        raise SystemExit("timeline: no rows for case %s" % args.case)

    by_run_variant = {(r["run_id"], model_key(r), variant_of(r)): r for r in rows}
    runs = sorted({r["run_id"] for r in rows})
    models = sorted({model_key(r) for r in rows})
    maxscore = rows[0]["max_score"]
    # rubric version comes from the history row: it is a property of the
    # case, while run-info.json describes the whole invocation
    rubrics = {}
    for r in rows:
        rubrics.setdefault(r["run_id"], r.get("rubric_version", 1))

    keys = [ruler_of(info_by_run.get(r, {}), rubrics.get(r)) for r in runs]
    n_rulers = len({k for k in keys})

    body = ['<h1>cfengine-policy skill &mdash; full history</h1>',
            '<p class="sub">every recorded run of <code>%s</code>, oldest first &middot; '
            'dot = mean, pale bar = spread across that run&rsquo;s repetitions</p>' % e(args.case)]

    body.append('<div class="card">')
    if n_rulers > 1:
        body.append('<p class="note" style="margin:0 0 12px">Each model is plotted on its own '
                    'run sequence, so the rows are not aligned in time with each other. '
                    'The thick pale bar behind a dot is the <b>spread across that run&rsquo;s '
                    'repetitions</b>, not movement between runs &mdash; an unaided variant routinely '
                    'varies by 70+ points from one repetition to the next. Shaded bands mark '
                    '<b>ruler regimes</b>: a change of rubric, of the engine the policy is '
                    'validated in, re-bases the score, so lines are deliberately broken at '
                    'every boundary. With only a run or two per model per regime there is not '
                    'much of a line yet &mdash; that fills in as runs accumulate.</p>')
    body.append('<div class="legend">'
                + "".join('<span><span class="swatch" style="background:%s"></span>%s</span>'
                          % ("var(--s1)" if a == "with-skill" else "var(--s2)", SERIES[a]["label"])
                          for a in VARIANTS) + '</div>')
    body.append(facets(runs, info_by_run, by_run_variant, models, maxscore, rubrics))

    trows = []
    for rid in runs:
        info = info_by_run.get(rid, {})
        rv, engine, delivery = ruler_of(info, rubrics.get(rid))
        for m in models:
            pair = {a: by_run_variant.get((rid, m, a)) for a in VARIANTS}
            if not any(pair.values()):
                continue
            cells = ""
            for a in VARIANTS:
                r = pair[a]
                cells += ('<td class="num">&mdash;</td><td class="num detail">&mdash;</td>'
                          if r is None else
                          '<td class="num">%.1f</td><td class="num detail">%g&ndash;%g</td>'
                          % (r["score_mean"], r["score_min"], r["score_max"]))
            d = ""
            if pair["with-skill"] and pair["no-skill"]:
                v = pair["with-skill"]["score_mean"] - pair["no-skill"]["score_mean"]
                d = '<span class="%s">%+.1f</span>' % ("pass" if v > 0 else "fail" if v < 0 else "detail", v)
            n = max((r["runs"] for r in pair.values() if r), default=0)
            sk = info.get("skill", {}).get("sha256", "")
            trows.append('<tr><td style="font-variant-numeric:tabular-nums">%s</td><td><b>%s</b></td>'
                         '<td class="num detail">%d</td>%s<td class="num">%s</td>'
                         '<td class="detail">v%s</td><td class="detail">%s</td>'
                         '<td class="detail">%s</td>'
                         '<td class="detail"><code>%s</code></td></tr>'
                         % (e(rid), e(m), n, cells, d, e(rv), e(engine), e(delivery),
                            e(sk[:8] or "?")))
    body.append('<details open><summary>Table view &mdash; every run, with the ruler it was '
                'scored against</summary><table><thead><tr><th>Run</th><th>Model</th>'
                '<th class="num">n</th><th class="num">No skill</th><th class="num">range</th>'
                '<th class="num">With skill</th><th class="num">range</th><th class="num">Delta</th>'
                '<th>Rubric</th><th>Engine</th><th>Delivery</th><th>Skill</th></tr></thead><tbody>%s</tbody>'
                '</table></details>' % "".join(trows))
    body.append('</div>')

    doc = ('<!doctype html><html lang="en"><head><meta charset="utf-8">'
           '<meta name="viewport" content="width=device-width,initial-scale=1">'
           '<title>cfengine-policy full history</title><style>%s</style></head><body>'
           '<button class="toggle">light / dark</button><div id="tt"></div>'
           '<div class="wrap">%s</div><script>%s</script></body></html>'
           % (CSS, "".join(body), JS))
    Path(args.out).write_text(doc)
    print("timeline: %s (%d runs, %d ruler regimes)" % (args.out, len(runs), n_rulers))


if __name__ == "__main__":
    main()
