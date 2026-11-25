#!/usr/bin/env python3
"""Aggregate one result directory into summary.json and append it to
history.jsonl for progression tracking. Idempotent: re-running replaces the
history rows for the same run id."""

import argparse
import json
import statistics
from pathlib import Path


def variant_of(row):
    """Recorded results predating the rename carry "arm"; read both."""
    return row.get("variant") or row.get("arm") or "?"


def mean(xs):
    return round(statistics.fmean(xs), 1) if xs else 0.0


# The score says whether the answer was right; these say what it cost to get
# there. Kept out of the score on purpose: a right-but-slow answer and a
# fast-but-partly-wrong one must not be able to trade places. On a case the
# unaided model can solve by exploring (mp-01-health), the skill's effect shows
# up here and nowhere else.
EFFICIENCY = {
    "turns": lambda cli: cli.get("num_turns"),
    "cost_usd": lambda cli: cli.get("total_cost_usd"),
    "duration_s": lambda cli: (cli.get("duration_ms") or 0) / 1000.0 if cli.get("duration_ms") else None,
}


def efficiency(rs):
    out = {}
    for name, get in EFFICIENCY.items():
        vals = [v for v in (get(r.get("cli") or {}) for r in rs) if v is not None]
        out[name] = {"mean": round(statistics.fmean(vals), 3) if vals else None,
                     "min": round(min(vals), 3) if vals else None,
                     "max": round(max(vals), 3) if vals else None}
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--run-dir", required=True)
    ap.add_argument("--history", required=True)
    args = ap.parse_args()

    run_dir = Path(args.run_dir)
    info_file = run_dir / "run-info.json"
    info = json.loads(info_file.read_text()) if info_file.exists() else {}
    run_id = run_dir.name

    results = sorted(run_dir.glob("*/*/run*/result.json"))
    if not results:
        raise SystemExit("aggregate: no result.json under %s" % run_dir)

    groups = {}
    for f in results:
        r = json.loads(f.read_text())
        groups.setdefault((r["case"], variant_of(r)), []).append(r)

    rows, summary = [], {"run_id": run_id, "info": info, "cases": {}}
    for (case, variant), rs in sorted(groups.items()):
        scores = [r["score"] for r in rs]
        checks = {}
        for cid in [c["id"] for c in rs[0]["checks"]]:
            earned = [next(c["earned"] for c in r["checks"] if c["id"] == cid) for r in rs]
            weight = next(c["weight"] for c in rs[0]["checks"] if c["id"] == cid)
            label = next(c["label"] for c in rs[0]["checks"] if c["id"] == cid)
            checks[cid] = {"label": label, "weight": weight, "earned_mean": mean(earned)}
        fns = [r.get("functional") for r in rs if r.get("functional")]
        functional = None
        if fns:
            ov = [len(f.get("overridden") or []) for f in fns]
            tot = [len(f.get("overridden") or []) + len(f.get("not_overridden") or []) for f in fns]
            counts = {}
            for f in fns:
                counts[f.get("status")] = counts.get(f.get("status"), 0) + 1
            functional = {
                "ran": any(f.get("ran") for f in fns),
                "status": fns[0].get("status") if len(counts) == 1 else "mixed",
                "counts": counts,
                "statuses": sorted(counts),
                "overridden": mean(ov),
                "total": mean(tot),
            }
        agg = {
            "runs": len(rs),
            "efficiency": efficiency(rs),
            "functional": functional,
            "score_mean": mean(scores),
            "score_min": min(scores),
            "score_max": max(scores),
            "max_score": rs[0]["max_score"],
            "checks": checks,
            "cost_usd": round(sum((r.get("cli") or {}).get("total_cost_usd") or 0 for r in rs), 4),
            "duration_ms": sum((r.get("cli") or {}).get("duration_ms") or 0 for r in rs),
        }
        summary["cases"].setdefault(case, {})[variant] = agg
        skill = info.get("skill", {})
        harness = info.get("harness", {})
        rows.append({
            "run_id": run_id,
            "timestamp": info.get("timestamp", run_id),
            "model": info.get("model", rs[0].get("model", "?")),
            "claude_code": harness.get("claude_code", "unknown"),
            "eval_commit": harness.get("eval_commit", "unknown"),
            "eval_dirty": harness.get("eval_dirty"),
            "case": case,
            "variant": variant,
            "skill_id": skill.get("id", "unknown"),
            "skill_commit": skill.get("commit", "unknown"),
            "skill_dirty": skill.get("dirty"),
            "skill_sha256": skill.get("sha256"),
            "runs": agg["runs"],
            "rubric_version": rs[0].get("rubric_version", 1),
            "score_mean": agg["score_mean"],
            "score_min": agg["score_min"],
            "score_max": agg["score_max"],
            "max_score": agg["max_score"],
            "checks": {k: v["earned_mean"] for k, v in checks.items()},
            # Flattened for timeline/compare, which read only history rows.
            **{"%s_%s" % (m, k): v for m, st in agg["efficiency"].items() for k, v in st.items()},
        })

    for case, variants in summary["cases"].items():
        if "with-skill" in variants and "no-skill" in variants:
            variants["delta"] = round(variants["with-skill"]["score_mean"] - variants["no-skill"]["score_mean"], 1)
            w, n = variants["with-skill"]["efficiency"], variants["no-skill"]["efficiency"]
            variants["efficiency_delta"] = {m: round(w[m]["mean"] - n[m]["mean"], 3)
                                            for m in w if m in n and w[m]["mean"] is not None
                                            and n[m]["mean"] is not None}
    (run_dir / "summary.json").write_text(json.dumps(summary, indent=2))

    hist = Path(args.history)
    hist.parent.mkdir(parents=True, exist_ok=True)
    kept = []
    if hist.exists():
        for line in hist.read_text().splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                if json.loads(line).get("run_id") != run_id:
                    kept.append(line)
            except ValueError:
                kept.append(line)
    kept += [json.dumps(r) for r in rows]
    hist.write_text("\n".join(kept) + "\n")

    for case, variants in sorted(summary["cases"].items()):
        parts = ["%s %.1f" % (a, variants[a]["score_mean"]) for a in ("no-skill", "with-skill") if a in variants]
        if "delta" in variants:
            parts.append("delta %+.1f" % variants["delta"])
        for a in ("no-skill", "with-skill"):
            ef = (variants.get(a) or {}).get("efficiency") or {}
            if ef.get("turns", {}).get("mean") is not None:
                parts.append("%s %.0f turns $%.2f" % (a, ef["turns"]["mean"], ef["cost_usd"]["mean"] or 0))
        print("aggregate: %-14s %s" % (case, "  ".join(parts)))


if __name__ == "__main__":
    main()
