#!/usr/bin/env python3
"""Analyze one eval variant: extract the generated policy, validate it with
cf-promises, check for hallucinated sys.* variables and for the
isvariable()/augments tunable pattern, then score against the case rubric.

Writes <variant-dir>/result.json and prints a one-line summary.
"""

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

# Identity redaction lives in scrub.py so run-eval.sh can apply the same rules
# to the captured workdir after analysis.
from scrub import allow_from, redact  # noqa: E402

CF_LANGS = {"cfengine3", "cfengine", "cf3", "cf", "cfengine-policy"}
FENCE_RE = re.compile(r"^```([A-Za-z0-9_+.-]*)[ \t]*\n(.*?)^```[ \t]*$", re.S | re.M)
COMMENT_RE = re.compile(r"^\s*#.*$", re.M)
SYSVAR_DEREF_RE = re.compile(r"\$[({]\s*(?:default:)?sys\.([A-Za-z0-9_]+)")
SYSVAR_BARE_RE = re.compile(r"(?<![\w.])(?:default:)?sys\.([A-Za-z0-9_]+)")
ISVAR_RE = re.compile(r'isvariable\s*\(\s*"([^"]+)"\s*\)')
IFELSE_ISVAR_RE = re.compile(r'ifelse\s*\(\s*isvariable\s*\(\s*"([^"]+)"\s*\)')
UNDEFINED_RE = re.compile(r"[Uu]ndefined (body|bundle)")
AGENT_BUNDLE_RE = re.compile(r"^\s*bundle\s+agent\s+([A-Za-z0-9_]+)\s*(\([^)]*\))?", re.M)
BUNDLE_RE = re.compile(r"^\s*bundle\s+(agent|common)\s+([A-Za-z0-9_]+)\s*(\([^)]*\))?", re.M)
BUNDLESEQ_RE = re.compile(r"\bbundlesequence\s*=>")
AUGMENTS_KEYS = {"vars", "classes", "inputs", "augments", "variables", "tags"}


def strip_comments(text):
    return COMMENT_RE.sub("", text)


def extract_fenced(md):
    return [(m.group(1).lower(), m.group(2)) for m in FENCE_RE.finditer(md)]


def looks_like_augments(obj):
    return isinstance(obj, dict) and bool(AUGMENTS_KEYS & set(obj.keys()))


def collect(variant_dir):
    """Return (policy_paths, root, augments_paths, sources)."""
    work = variant_dir / "workdir"
    extracted = variant_dir / "extracted"
    response = ""
    resp_file = variant_dir / "response.md"
    if resp_file.exists():
        response = resp_file.read_text(errors="replace")
    blocks = extract_fenced(response)

    cf_paths = sorted(p for p in work.rglob("*.cf") if p.is_file()) if work.is_dir() else []
    policy_source = "workdir"
    root = work

    if not cf_paths:
        extracted.mkdir(exist_ok=True)
        for i, (lang, code) in enumerate(b for b in blocks if b[0] in CF_LANGS):
            p = extracted / f"policy-{i:02d}.cf"
            p.write_text(code)
            cf_paths.append(p)
        policy_source = "response" if cf_paths else "none"
        root = extracted

    aug_paths = []
    if work.is_dir():
        for p in sorted(work.rglob("*.json")):
            try:
                if looks_like_augments(json.loads(p.read_text(errors="replace"))):
                    aug_paths.append(p)
            except (ValueError, OSError):
                continue
    augments_source = "workdir" if aug_paths else "none"

    if not aug_paths:
        extracted.mkdir(exist_ok=True)
        for i, (lang, code) in enumerate(b for b in blocks if b[0] == "json"):
            try:
                if not looks_like_augments(json.loads(code)):
                    continue
            except ValueError:
                continue
            p = extracted / f"def-{i:02d}.json"
            p.write_text(code)
            aug_paths.append(p)
        augments_source = "response" if aug_paths else "none"

    return cf_paths, root, aug_paths, {"policy": policy_source, "augments": augments_source}


def stage(root, cf_paths, stdlib=None):
    """Copy the policy tree to a scratch dir (optionally stdlib-wrapped).
    Returns (staging_dir, [relative cf paths])."""
    dest = Path(tempfile.mkdtemp(prefix="cfeval-validate."))
    rels = []
    if root.is_dir():
        for src in sorted(root.rglob("*")):
            if not src.is_file():
                continue
            rel = src.relative_to(root)
            out = dest / rel
            out.parent.mkdir(parents=True, exist_ok=True)
            if src.suffix == ".cf":
                text = src.read_text(errors="replace")
                if stdlib:
                    text = 'body file control\n{\n  inputs => { "%s" };\n}\n\n' % stdlib + text
                out.write_text(text)
                out.chmod(0o600)
            else:
                shutil.copy2(src, out)
    for p in cf_paths:
        rels.append(p.relative_to(root).as_posix())
    return dest, rels


def entry_points(rels):
    named = [r for r in rels if Path(r).name in ("promises.cf", "main.cf")]
    return named or rels


# Set from --image. Running cf-promises/cf-agent in a container rather than on
# the host keeps the machine's identity out of sys.* (cf-agent reports the real
# sys.bindir and sys.uqhost otherwise), stops model-generated policy from being
# evaluated on the workstation, and pins the CFEngine version so scores from
# different machines are comparable.
CONTAINER = {"image": None}


def run(cmd, cwd, timeout=120):
    if CONTAINER["image"]:
        # $(sys.libdir) resolves to /var/cfengine/inputs/lib, which only exists
        # once an agent is bootstrapped; the image ships masterfiles only. Link
        # it so "$(sys.libdir)/stdlib.cf" -- the standard idiom -- resolves.
        prep = ("mkdir -p /var/cfengine/inputs && "
                "ln -sfn /var/cfengine/masterfiles/lib /var/cfengine/inputs/lib; exec ")
        inner = " ".join(shlex.quote(c) for c in cmd)
        cmd = ["podman", "run", "--rm", "--network=none", "--hostname", "cfeval",
               "-v", "%s:/policy:Z" % cwd, "-w", "/policy",
               CONTAINER["image"], "sh", "-c", prep + inner]
        cwd = None
        timeout += 60  # container startup
    try:
        cp = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return cp.returncode, (cp.stdout or "") + (cp.stderr or "")
    except subprocess.TimeoutExpired:
        return 124, "timed out after %ss" % timeout
    except OSError as e:
        return 127, str(e)


def resolve_engine(image):
    """Return (image_or_None, description). Falls back to host binaries with a
    warning so the harness still runs where podman or the image is missing."""
    if not image:
        return None, "host"
    if shutil.which("podman") is None:
        print("analyze: podman not found, falling back to host binaries", file=sys.stderr)
        return None, "host (podman missing)"
    rc = subprocess.run(["podman", "image", "exists", image]).returncode
    if rc != 0:
        print("analyze: image %s not present, falling back to host binaries" % image,
              file=sys.stderr)
        return None, "host (image missing)"
    return image, "container %s" % image


ENTRY_BUNDLES = ("main", "__main__")


def parameterless_bundles(text):
    """Agent bundles taking no arguments, else common bundles taking none.
    main/__main__ are excluded: cf-promises rejects them in an explicit
    bundlesequence even when the policy defines them."""
    agent, common = [], []
    for m in BUNDLE_RE.finditer(strip_comments(text)):
        if (m.group(3) or "()").strip("() \t"):
            continue
        if m.group(2) in ENTRY_BUNDLES:
            continue
        (agent if m.group(1) == "agent" else common).append(m.group(2))
    return agent or common


def cf_promises(stage_dir, rels):
    """Validate each entry point. cf-promises defaults to a bundlesequence of
    'main'; a policy that only defines library bundles would fail on that
    harness artifact alone, so synthesize a bundlesequence when the policy
    declares neither 'main' nor its own."""
    all_text = "\n".join((Path(stage_dir) / r).read_text(errors="replace") for r in rels)
    needs_seq = not BUNDLESEQ_RE.search(all_text) and not re.search(
        r"^\s*bundle\s+agent\s+(main|__main__)\b", strip_comments(all_text), re.M)
    results = []
    for i, rel in enumerate(entry_points(rels)):
        bundles = parameterless_bundles((Path(stage_dir) / rel).read_text(errors="replace"))
        target, seq = rel, None
        if needs_seq and bundles:
            # A synthetic entry file, not cf-promises -b: passing -b makes
            # cf-promises skip the undefined body/bundle checks entirely.
            seq = ",".join(bundles)
            harness = Path(stage_dir) / ("cfeval-entry-%d.cf" % i)
            harness.write_text(
                'body common control\n{\n  inputs => { "%s" };\n  bundlesequence => { %s };\n}\n'
                % (rel, ", ".join('"%s"' % b for b in bundles)))
            harness.chmod(0o600)
            target = harness.name
        rc, out = run(["cf-promises", "-c", "-f", "./" + target], cwd=stage_dir)
        results.append({"file": rel, "rc": rc, "output": redact(out.strip()),
                        "bundlesequence": seq})
    return results


def validate(root, cf_paths, stdlib):
    """Standalone cf-promises first; retry with stdlib on undefined body/bundle."""
    v = {
        "attempted": bool(cf_paths),
        "standalone_ok": False,
        "standalone": [],
        "stdlib_retried": False,
        "stdlib_ok": None,
        "stdlib": [],
        "stdlib_path": stdlib,
    }
    if not cf_paths:
        return v

    d1, rels = stage(root, cf_paths)
    try:
        v["standalone"] = cf_promises(d1, rels)
    finally:
        shutil.rmtree(d1, ignore_errors=True)
    v["standalone_ok"] = bool(v["standalone"]) and all(r["rc"] == 0 for r in v["standalone"])

    if not v["standalone_ok"] and stdlib and os.path.exists(stdlib):
        if any(UNDEFINED_RE.search(r["output"]) for r in v["standalone"]):
            v["stdlib_retried"] = True
            d2, rels2 = stage(root, cf_paths, stdlib=stdlib)
            try:
                v["stdlib"] = cf_promises(d2, rels2)
            finally:
                shutil.rmtree(d2, ignore_errors=True)
            v["stdlib_ok"] = bool(v["stdlib"]) and all(r["rc"] == 0 for r in v["stdlib"])
    return v


def check_sys_vars(policy_text, known):
    body = strip_comments(policy_text)
    refs = set(SYSVAR_DEREF_RE.findall(body)) | set(SYSVAR_BARE_RE.findall(body))
    unknown = sorted(r for r in refs if r not in known)
    return {"referenced": sorted(refs), "unknown": unknown, "known_count": len(known)}


def base_name(ref):
    return ref.rsplit(".", 1)[-1]


def qualify(name):
    """Normalize a variable reference to namespace:bundle.var. A bare def.json
    key lands in the def bundle of the default namespace."""
    if "." not in name:
        name = "def." + name
    if ":" not in name:
        name = "default:" + name
    return name


def augments_targets(obj):
    """Fully-qualified variable names a def.json defines. CFEngine accepts both
    "vars" (bare name -> value) and "variables" (name -> {value, comment, tags});
    both were verified to drive the override on this host."""
    out = set()
    for section in ("vars", "variables"):
        d = obj.get(section)
        if isinstance(d, dict):
            out |= {qualify(k) for k in d}
    return out


def check_patterns(policy_text, aug_paths):
    body = strip_comments(policy_text)
    all_isvar = set(ISVAR_RE.findall(body))
    tunables = sorted(r for r in all_isvar if "def." in r)
    instrumented = sorted(set(IFELSE_ISVAR_RE.findall(body)) & set(tunables))
    fully_qualified = sorted(t for t in tunables if t.startswith("default:def."))

    aug_keys, aug_files = set(), []
    for p in aug_paths:
        try:
            obj = json.loads(p.read_text(errors="replace"))
        except (ValueError, OSError):
            continue
        aug_files.append(p.name)
        aug_keys |= augments_targets(obj)

    wanted = {qualify(t) for t in tunables}
    return {
        "isvariable_refs": sorted(all_isvar),
        "tunables": tunables,
        "instrumented": instrumented,
        "fully_qualified": fully_qualified,
        "augments_files": aug_files,
        "augments_keys": sorted(aug_keys),
        "matched_keys": sorted(wanted & aug_keys),
        "unmatched_tunables": sorted(wanted - aug_keys),
    }


def functional_check(root, cf_paths, patterns, stdlib):
    """Opt-in: dry-run the policy with and without a synthetic def.json and see
    whether the tunables actually change value."""
    out = {"ran": False, "status": "skipped", "overridden": [], "not_overridden": [], "log": ""}
    keys = [base_name(t) for t in patterns["tunables"]]
    if not keys or not cf_paths:
        out["status"] = "no tunables"
        return out

    d, rels = stage(root, cf_paths, stdlib=stdlib if stdlib and os.path.exists(stdlib) else None)
    try:
        entry = entry_points(rels)[0]
        all_text = "\n".join((Path(d) / r).read_text(errors="replace") for r in rels)
        cmd = ["cf-agent", "-Kn", "-f", "./" + entry]
        if not BUNDLESEQ_RE.search(all_text):
            bundles = parameterless_bundles((Path(d) / entry).read_text(errors="replace"))
            if not bundles:
                out["status"] = "no bundlesequence and no parameterless agent bundle"
                return out
            cmd += ["-b", ",".join(bundles)]
        sentinel = {k: "CFEVALSENTINEL_" + k for k in keys}
        (Path(d) / "def.json").write_text(json.dumps({"vars": sentinel}, indent=2))
        cmd += ["--show-evaluated-vars=.*"]
        rc, log = run(cmd, cwd=d, timeout=180)
        out["ran"] = True
        # Only the lines about the tunables. The full dump is every sys.* var,
        # which is both noise and machine-identifying.
        keep = [l for l in log.splitlines()
                if "CFEVALSENTINEL_" in l or any(k in l for k in keys)]
        out["log"] = redact("\n".join(keep[-60:]))
        for k in keys:
            (out["overridden"] if ("CFEVALSENTINEL_" + k) in log else out["not_overridden"]).append(k)
        out["status"] = "ok" if out["overridden"] and not out["not_overridden"] else (
            "partial" if out["overridden"] else "no override observed")
    finally:
        shutil.rmtree(d, ignore_errors=True)
    return out


def score(case, validation, sysvars, patterns):
    w = case["weights"]
    need = case.get("expect", {}).get("min_tunables", 3)
    checks = []

    def add(cid, label, weight, earned, detail):
        checks.append({"id": cid, "label": label, "weight": weight,
                       "earned": round(earned, 2), "detail": detail})

    if validation["standalone_ok"]:
        add("validate", "Policy passes cf-promises standalone", w["validate"], w["validate"],
            "cf-promises -cf clean")
    elif validation.get("stdlib_ok"):
        add("validate", "Policy passes cf-promises standalone", w["validate"], w["validate"] * 0.6,
            "needed stdlib.cf to resolve undefined body/bundle")
    else:
        first = ""
        for r in validation.get("standalone", []):
            if r["rc"] != 0:
                first = r["output"].splitlines()[0] if r["output"] else "rc=%d" % r["rc"]
                break
        add("validate", "Policy passes cf-promises standalone", w["validate"], 0,
            first or "no policy found")

    n_unknown = len(sysvars["unknown"])
    add("sys_vars", "No hallucinated sys.* variables", w["sys_vars"],
        w["sys_vars"] if n_unknown == 0 else 0,
        "clean (%d referenced)" % len(sysvars["referenced"]) if n_unknown == 0
        else "unknown: " + ", ".join("sys." + u for u in sysvars["unknown"]))

    n_tun = len(patterns["tunables"])
    add("tunable_count", "%d augments tunables present" % need, w["tunable_count"],
        w["tunable_count"] * min(n_tun, need) / need, "%d found" % n_tun)

    n_inst = len(patterns["instrumented"])
    add("isvariable_pattern", "ifelse(isvariable(...)) instrumentation", w["isvariable_pattern"],
        w["isvariable_pattern"] * min(n_inst, need) / need,
        "%d of %d tunables wrapped in ifelse()" % (n_inst, max(n_tun, 1)) if n_tun
        else "no isvariable() on def vars")

    # SKILL.md accepts either form: fully qualify across namespaces, and
    # `def.varname` "works fine" within the default namespace. So both earn full
    # credit; only an inconsistent mix is marked down.
    n_fq = len(patterns["fully_qualified"])
    label = "Tunables namespaced consistently"
    if not n_tun:
        add("qualified_refs", label, w["qualified_refs"], 0, "no tunables")
    elif n_fq in (0, n_tun):
        add("qualified_refs", label, w["qualified_refs"], w["qualified_refs"],
            "all %s" % ("fully qualified (default:def.)" if n_fq else "bare def."))
    else:
        add("qualified_refs", label, w["qualified_refs"], w["qualified_refs"] * 0.5,
            "mixed: %d of %d fully qualified" % (n_fq, n_tun))

    has_aug = bool(patterns["augments_files"]) and bool(patterns["augments_keys"])
    add("augments_example", "def.json augments example provided", w["augments_example"],
        w["augments_example"] if has_aug else 0,
        ", ".join(patterns["augments_files"]) if has_aug else "none")

    n_match = len(patterns["matched_keys"])
    add("augments_keys_match", "def.json keys match policy tunables", w["augments_keys_match"],
        w["augments_keys_match"] * min(n_match, need) / need, "%d matched" % n_match)

    total = sum(c["earned"] for c in checks)
    return checks, round(total, 1), sum(c["weight"] for c in checks)


def analyze_mission_portal(case, variant_dir):
    """No policy to validate: the live hub is the oracle. See grade_mp.py."""
    import grade_mp
    checks, total, maxscore, detail = grade_mp.grade(case, variant_dir)
    meta_file = variant_dir / "meta.json"
    result = json.loads(meta_file.read_text()) if meta_file.exists() else {}
    script = [detail["script"]] if detail["script"] else []
    result.update({
        "case": case["id"],
        "case_title": case.get("title", case["id"]),
        "rubric_version": case.get("rubric_version", 1),
        # Shaped like a policy result so report.py can show the script in the
        # slot it uses for generated policy.
        "artifacts": {"policy_files": script, "augments_files": [],
                      "sources": {"policy": "script" if script else "none"},
                      "policy_bytes": 0},
        "engine": "live hub %s" % os.environ.get("MP_URL", "?"),
        "validation": {},
        "grader": "mission-portal",
        "hub": detail,
        "checks": checks,
        "score": total,
        "max_score": maxscore,
    })
    (variant_dir / "result.json").write_text(json.dumps(result, indent=2))
    print("%-11s score %5.1f/%d  rc=%s  expected=%d  got=%d"
          % (result.get("variant", "?"), total, maxscore, detail["exit_code"],
             len(detail["expected"]), len(detail["got"])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant-dir", "--arm-dir", dest="variant_dir",
                    required=True, help="the run directory to analyze")
    ap.add_argument("--case-file", required=True)
    ap.add_argument("--sys-vars", required=True)
    ap.add_argument("--stdlib", default="/var/cfengine/masterfiles/lib/stdlib.cf")
    ap.add_argument("--functional", action="store_true")
    ap.add_argument("--allow-from", action="append", default=[],
                    help="file whose email addresses are example content, not identity")
    ap.add_argument("--image", default=os.environ.get("CFEVAL_IMAGE", ""),
                    help="container image for cf-promises/cf-agent; empty = host binaries")
    args = ap.parse_args()

    # Addresses the model was shown are example content; see scrub.py.
    allow_from(*args.allow_from)

    CONTAINER["image"], engine = resolve_engine(args.image)

    variant_dir = Path(args.variant_dir)
    case = json.loads(Path(args.case_file).read_text())
    if case.get("grader") == "mission-portal":
        return analyze_mission_portal(case, variant_dir)
    known = {l.strip() for l in Path(args.sys_vars).read_text().splitlines() if l.strip()}

    cf_paths, root, aug_paths, sources = collect(variant_dir)
    policy_text = "\n".join(p.read_text(errors="replace") for p in cf_paths)

    validation = validate(root, cf_paths, args.stdlib)
    sysvars = check_sys_vars(policy_text, known)
    patterns = check_patterns(policy_text, aug_paths)
    functional = functional_check(root, cf_paths, patterns, args.stdlib) if args.functional else None
    checks, total, maxscore = score(case, validation, sysvars, patterns)

    meta = {}
    meta_file = variant_dir / "meta.json"
    if meta_file.exists():
        meta = json.loads(meta_file.read_text())

    result = dict(meta)
    result.update({
        "case": case["id"],
        "case_title": case.get("title", case["id"]),
        "rubric_version": case.get("rubric_version", 1),
        "artifacts": {
            "policy_files": [p.name for p in cf_paths],
            "augments_files": [p.name for p in aug_paths],
            "sources": sources,
            "policy_bytes": len(policy_text),
        },
        "engine": engine,
        "validation": validation,
        "sys_vars": sysvars,
        "patterns": patterns,
        "functional": functional,
        "checks": checks,
        "score": total,
        "max_score": maxscore,
    })
    (variant_dir / "result.json").write_text(json.dumps(result, indent=2))
    print("%-11s score %5.1f/%d  validate=%s  unknown_sys=%d  tunables=%d  instrumented=%d  augments=%s"
          % (result.get("variant", "?"), total, maxscore,
             "ok" if validation["standalone_ok"] else ("stdlib" if validation.get("stdlib_ok") else "FAIL"),
             len(sysvars["unknown"]), len(patterns["tunables"]),
             len(patterns["instrumented"]),
             "yes" if patterns["augments_files"] else "no"))


if __name__ == "__main__":
    main()
