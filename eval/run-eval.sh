#!/usr/bin/env bash
# Persistent eval harness for the cfengine-policy skill.
#
# Runs each case prompt twice -- once with the skill exposed via --add-dir and
# once without -- in a throwaway jail, then validates the generated policy with
# cf-promises, checks it against this host's real sys.* variables, scores the
# augments/isvariable instrumentation, and writes a timestamped result set
# stamped with the skill's git hash so progression is tracked across revisions.
#
#   ./eval/run-eval.sh                         # all cases, sonnet, both variants
#   ./eval/run-eval.sh --case 01-motd --runs 3
#   ./eval/run-eval.sh --report-only           # rebuild the report from results
set -euo pipefail

EVAL_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_DIR=$(cd "$EVAL_DIR/.." && pwd)
SKILL_DIR="$REPO_DIR/cfengine-policy"
SKILL_MD="$SKILL_DIR/SKILL.md"
STDLIB=${CFEVAL_STDLIB:-/var/cfengine/masterfiles/lib/stdlib.cf}
# cf-promises / cf-agent run here, not on the host: keeps the machine's identity
# out of sys.*, keeps generated policy off the workstation, and pins the
# CFEngine version so scores are comparable across machines.
IMAGE=${CFEVAL_IMAGE:-localhost/cfengine-test:3.27.0}

MODEL=sonnet
RUNS=1
VARIANTS="both"
TIMEOUT=900
LABEL=""
OPEN_REPORT=1
REPORT_ONLY=0
FUNCTIONAL=0
SAFE_PERMS=0
# The with-skill side installs the skill into the jail's own skills directory so
# Claude Code loads it for real -- executing its dynamic blocks, which is what
# supplies the documentation paths. Handing over a raw SKILL.md via --add-dir
# graded a file no real user is ever given.
DOCS_DIR=${CFENGINE_DOCS_DIR:-$HOME/.local/share/cfengine/docs}
DOCS_BRANCH=""
DOCS_COMMIT=""
declare -a CASES=()

die() { echo "run-eval: $*" >&2; exit 1; }

usage() {
  sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
  cat <<'USAGE'

Options:
  --case ID          case to run (repeatable; default: every dir in eval/cases)
  --model NAME       model alias passed to claude (default: sonnet)
  --runs N           repetitions per variant, for variance (default: 1)
  --variant VARIANT          both | with-skill | no-skill (default: both)
  --label TEXT       suffix appended to the result directory name
  --timeout SECS     per-invocation timeout (default: 900)
  --functional       additionally dry-run the policy to prove augments override
  --image REF        container image for cf-promises/cf-agent
                     (default: localhost/cfengine-test:3.27.0, or $CFEVAL_IMAGE)
  --no-container     use the host's cf-promises/cf-agent instead
  --safe-perms       scoped permissions instead of --dangerously-skip-permissions
  --no-open          do not launch a browser for the report
  --report-only      regenerate report/history from existing results and exit
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --case)        CASES+=("$2"); shift 2 ;;
    --model)       MODEL=$2; shift 2 ;;
    --runs)        RUNS=$2; shift 2 ;;
    --variant)         VARIANTS=$2; shift 2 ;;
    --arm)             VARIANTS=$2; shift 2 ;;   # pre-rename alias, undocumented
    --label)       LABEL=$2; shift 2 ;;
    --timeout)     TIMEOUT=$2; shift 2 ;;
    --functional)  FUNCTIONAL=1; shift ;;
    --image)       IMAGE=$2; shift 2 ;;
    --no-container) IMAGE=""; shift ;;
    --safe-perms)  SAFE_PERMS=1; shift ;;
    --no-open)     OPEN_REPORT=0; shift ;;
    --report-only) REPORT_ONLY=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "unknown option: $1 (try --help)" ;;
  esac
done

command -v python3 >/dev/null || die "missing required tool: python3"

# --report-only rebuilds HTML from committed result.json files: no model calls,
# no CFEngine, so a fresh clone can read the results with nothing else installed.
ENGINE="n/a (report-only)"
if [ "$REPORT_ONLY" != 1 ]; then
  command -v claude >/dev/null || die "missing required tool: claude"
  if [ -n "$IMAGE" ] && command -v podman >/dev/null 2>&1 && podman image exists "$IMAGE" 2>/dev/null; then
    ENGINE="container $IMAGE"
  else
    [ -n "$IMAGE" ] && echo "run-eval: $IMAGE unavailable, falling back to host binaries" >&2
    IMAGE=""
    ENGINE="host"
    for tool in cf-promises cf-agent; do
      command -v "$tool" >/dev/null || die "missing required tool: $tool (and no usable image)"
    done
  fi
fi
[ -f "$SKILL_MD" ] || die "skill not found: $SKILL_MD"

if [ ${#CASES[@]} -eq 0 ]; then
  while IFS= read -r d; do CASES+=("$(basename "$d")"); done \
    < <(find "$EVAL_DIR/cases" -mindepth 1 -maxdepth 1 -type d | sort)
fi
[ ${#CASES[@]} -gt 0 ] || die "no cases found under $EVAL_DIR/cases"

case "$VARIANTS" in
  both)       VARIANT_LIST=(no-skill with-skill) ;;
  with-skill) VARIANT_LIST=(with-skill) ;;
  no-skill)   VARIANT_LIST=(no-skill) ;;
  *)          die "--variant must be both, with-skill or no-skill" ;;
esac

# --- skill identity: what this run is measuring --------------------------------
SKILL_COMMIT=$(git -C "$REPO_DIR" log -1 --format=%H -- cfengine-policy/SKILL.md 2>/dev/null || true)
[ -n "$SKILL_COMMIT" ] || SKILL_COMMIT="uncommitted"
if git -C "$REPO_DIR" status --porcelain -- cfengine-policy/SKILL.md 2>/dev/null | grep -q .; then
  SKILL_DIRTY=true
else
  SKILL_DIRTY=false
fi
SKILL_SHA=$(sha256sum "$SKILL_MD" | cut -d' ' -f1)
SKILL_ID="${SKILL_COMMIT:0:8}"
[ "$SKILL_DIRTY" = true ] && SKILL_ID="${SKILL_ID}+dirty.${SKILL_SHA:0:8}"

HISTORY="$EVAL_DIR/results/history.jsonl"
SYS_VARS="$EVAL_DIR/cache/sys-vars.txt"

if [ "$REPORT_ONLY" = 1 ]; then
  RUN_DIR=$(find "$EVAL_DIR/results" -mindepth 1 -maxdepth 1 -type d | sort | tail -1)
  [ -n "$RUN_DIR" ] || die "no result directories to report on"
else
  TS=$(date +%Y%m%d-%H%M%S)
  RUN_DIR="$EVAL_DIR/results/$TS${LABEL:+-$LABEL}"
  mkdir -p "$RUN_DIR"

  "$EVAL_DIR/bin/refresh-sys-vars.sh" "$SYS_VARS" "$IMAGE"

  # --- what the installed skill will pull in ------------------------------
  # Recorded for provenance: the skill's own script clones/updates this, and the
  # docs revision is part of what the with-skill side was given.
  if [ -d "$DOCS_DIR/.git" ]; then
    DOCS_BRANCH=$(git -C "$DOCS_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || true)
    DOCS_COMMIT=$(git -C "$DOCS_DIR" rev-parse HEAD 2>/dev/null || true)
    echo "run-eval: docs $DOCS_BRANCH @ ${DOCS_COMMIT:0:8}"
  else
    echo "run-eval: no docs checkout yet; the skill will clone it on first load" >&2
  fi

  # strip characters that would break the JSON literal below
  if [ -n "$IMAGE" ]; then
    CF_VERSION=$(podman run --rm "$IMAGE" cf-promises --version 2>/dev/null | head -1 | tr -d '"\\')
  else
    CF_VERSION=$(cf-promises --version | head -1 | tr -d '"\\')
  fi
  CC_VERSION=$(claude --version 2>/dev/null | head -1 | tr -d '"\\')
  # The eval code is itself a variable: a scoring change moves the number just
  # as a skill change does, so stamp it alongside the skill.
  EVAL_COMMIT=$(git -C "$REPO_DIR" log -1 --format=%H -- eval 2>/dev/null || true)
  [ -n "$EVAL_COMMIT" ] || EVAL_COMMIT="uncommitted"
  if git -C "$REPO_DIR" status --porcelain -- eval 2>/dev/null | grep -q .; then
    EVAL_DIRTY=true
  else
    EVAL_DIRTY=false
  fi
  cat > "$RUN_DIR/run-info.json" <<JSON
{
  "timestamp": "$TS",
  "label": "$LABEL",
  "model": "$MODEL",
  "runs_per_variant": $RUNS,
  "variants": "$VARIANTS",
  "functional": $([ "$FUNCTIONAL" = 1 ] && echo true || echo false),
  "cfengine": "$CF_VERSION",
  "engine": "$ENGINE",
  "platform": "$(uname -s)-$(uname -m)",
  "harness": {
    "claude_code": "$CC_VERSION",
    "eval_commit": "$EVAL_COMMIT",
    "eval_dirty": $EVAL_DIRTY
  },
  "skill_delivery": "installed",
  "docs": {
    "branch": "$DOCS_BRANCH",
    "commit": "$DOCS_COMMIT"
  },
  "skill": {
    "path": "cfengine-policy/SKILL.md",
    "commit": "$SKILL_COMMIT",
    "dirty": $SKILL_DIRTY,
    "sha256": "$SKILL_SHA",
    "id": "$SKILL_ID",
    "bytes": $(wc -c < "$SKILL_MD")
  }
}
JSON
  cp "$SKILL_MD" "$RUN_DIR/SKILL.md.snapshot"
fi

# --- one model invocation in a throwaway jail ----------------------------------
run_variant() {
  local case_id=$1 variant=$2 idx=$3
  local case_dir="$EVAL_DIR/cases/$case_id"
  local out="$RUN_DIR/$case_id/$variant/run$(printf '%02d' "$idx")"
  mkdir -p "$out"

  local jail
  jail=$(mktemp -d "${TMPDIR:-/tmp}/cfeval-${case_id}-${variant}.XXXXXXXX")
  mkdir -p "$jail/work" "$jail/config"
  # Fresh CLAUDE_CONFIG_DIR: no user CLAUDE.md, no pre-installed skills, no
  # plugins, no project settings. The skill under test is installed into this
  # directory below, so it is the only difference between the two sides.
  cp "$HOME/.claude/.credentials.json" "$jail/config/" 2>/dev/null || true

  local sysprompt
  sysprompt=$(cat "$EVAL_DIR/lib/base-system-prompt.txt")
  if [ "$variant" = with-skill ]; then
    # Install into the jail's skills directory, flat -- Claude Code discovers
    # skills/<name>/SKILL.md and does not recurse, so a nested copy is invisible.
    # Copied rather than symlinked into the repo: a symlink would let the model
    # walk up into eval/results and read every other run's answer.
    mkdir -p "$jail/config/skills"
    cp -a "$SKILL_DIR" "$jail/config/skills/cfengine-policy"
    # The skill resolves its helpers as ${CLAUDE_SKILL_DIR}/../scripts.
    cp -a "$REPO_DIR/scripts" "$jail/config/skills/scripts"
    sysprompt="$sysprompt"$'\n'"$(cat "$EVAL_DIR/lib/skill-system-prompt.txt")"
  fi

  # --disable-slash-commands is deliberately absent: it also makes installed
  # skills unavailable, which silently turned the with-skill side into a second
  # baseline. A fresh config dir has no custom commands to guard against anyway.
  local -a perms=(--dangerously-skip-permissions)
  [ "$SAFE_PERMS" = 1 ] && perms=(--permission-mode acceptEdits --permission-prompts none)

  local prompt
  prompt=$(cat "$case_dir/prompt.txt")
  SKILL_SHA_BEFORE=$(sha256sum "$SKILL_MD" | cut -d' ' -f1)

  {
    printf '#!/bin/sh\n# Re-run this variant exactly as the harness did. A fresh jail is created;\n'
    printf '# its path is printed at the end so the artifacts can be inspected.\n'
    printf 'set -e\nHERE=$(cd "$(dirname "$0")" && pwd)\n'
    # repo-relative, so the reproduce script carries no absolute path:
    # <repo>/eval/results/<ts>/<case>/<side>/runNN -> six levels up
    printf 'REPO=$(cd "$HERE/../../../../../.." && pwd)\n'
    printf 'JAIL=$(mktemp -d "${TMPDIR:-/tmp}/cfeval-replay.XXXXXXXX")\n'
    printf 'mkdir -p "$JAIL/work" "$JAIL/config"\n'
    printf 'cp "$HOME/.claude/.credentials.json" "$JAIL/config/" 2>/dev/null || true\n'
    if [ "$variant" = with-skill ]; then
      printf 'mkdir -p "$JAIL/config/skills"\n'
      printf 'cp -a "$REPO/cfengine-policy" "$JAIL/config/skills/cfengine-policy"\n'
      printf 'cp -a "$REPO/scripts" "$JAIL/config/skills/scripts"\n'
      printf 'export CFENGINE_SKILL_UPDATE_DISABLE=1\n'
    fi
    printf 'cd "$JAIL/work"\n'
    printf 'CLAUDE_CONFIG_DIR="$JAIL/config" claude \\\n'
    printf '  -p "$(cat \"$HERE/prompt.txt\")" \\\n'
    printf '  --model %s --output-format json \\\n' "$MODEL"
    printf '  --append-system-prompt "$(cat \"$HERE/system-prompt.txt\")" \\\n'
    printf '  --strict-mcp-config --no-session-persistence \\\n'
    printf '  %s' "${perms[*]}"
    printf '\necho "jail: $JAIL"\n'
  } > "$out/cmd.sh"
  chmod +x "$out/cmd.sh"
  cp "$case_dir/prompt.txt" "$out/prompt.txt"

  echo "  -> $case_id/$variant run$idx (jail: $jail)"
  local rc=0
  ( cd "$jail/work" && CLAUDE_CONFIG_DIR="$jail/config" \
      CFENGINE_SKILL_UPDATE_DISABLE=1 timeout "$TIMEOUT" claude \
      -p "$prompt" \
      --model "$MODEL" \
      --output-format json \
      --append-system-prompt "$sysprompt" \
      --strict-mcp-config \
      --no-session-persistence \
      "${perms[@]}" ) > "$out/raw.json" 2> "$out/stderr.log" || rc=$?

  SKILL_SHA_AFTER=$(sha256sum "$SKILL_MD" | cut -d' ' -f1)

  SYSPROMPT="$sysprompt" python3 - "$out" "$rc" "$variant" "$idx" "$MODEL" \
      "$SKILL_SHA_BEFORE" "$SKILL_SHA_AFTER" <<'PY'
import json, os, sys
from pathlib import Path
out, rc, variant, idx, model = Path(sys.argv[1]), int(sys.argv[2]), sys.argv[3], int(sys.argv[4]), sys.argv[5]
sha_before, sha_after = sys.argv[6], sys.argv[7]



raw = (out / "raw.json").read_text(errors="replace") if (out / "raw.json").exists() else ""
cli, text = {}, raw
try:
    obj = json.loads(raw)
    text = obj.get("result", "") or ""
    cli = {k: obj.get(k) for k in
           ("duration_ms", "duration_api_ms", "num_turns", "total_cost_usd", "is_error", "subtype")}
    usage = obj.get("modelUsage") or {}
except ValueError:
    cli, usage = {"parse_error": True}, {}
# Written verbatim; bin/scrub.py redacts this whole directory after analysis.
(out / "response.md").write_text(text)
(out / "system-prompt.txt").write_text(os.environ.get("SYSPROMPT", ""))
meta = {"variant": variant, "run": idx, "model": model, "exit_code": rc, "cli": cli,
        "skill_sha256": sha_before}
# --model takes an alias that resolves to whatever is newest, so record what it
# resolved to. Claude Code also calls a small model for housekeeping; the run's
# model is the one that wrote the most output.
if usage:
    meta["model_id"] = max(usage, key=lambda m: usage[m].get("outputTokens") or 0)
    meta["models_used"] = sorted(usage)
if sha_before != sha_after:
    # The skill was edited while this run was in flight: its result cannot be
    # attributed to either revision.
    meta["skill_changed_during_run"] = True
    meta["skill_sha256_after"] = sha_after
    print("run-eval: WARNING skill changed during %s run%d -- result not attributable"
          % (variant, idx), file=sys.stderr)
(out / "meta.json").write_text(json.dumps(meta, indent=2))
PY

  mkdir -p "$out/workdir"
  cp -a "$jail/work/." "$out/workdir/" 2>/dev/null || true
  rm -rf "$jail"

  local -a an=(--variant-dir "$out" --case-file "$case_dir/case.json"
               --sys-vars "$SYS_VARS" --stdlib "$STDLIB" --image "$IMAGE"
               --allow-from "$SKILL_MD" --allow-from "$case_dir/prompt.txt")
  [ "$FUNCTIONAL" = 1 ] && an+=(--functional)
  python3 "$EVAL_DIR/bin/analyze.py" "${an[@]}"

  # Scrub only after analysis, so cf-promises validates the bytes the model
  # actually wrote rather than the redacted copy. The model's own inputs form
  # the allowlist: an address the skill taught is example content, an address
  # that appears from nowhere else came out of the injected user context.
  python3 "$EVAL_DIR/bin/scrub.py" \
      --allow-from "$SKILL_MD" --allow-from "$case_dir/prompt.txt" "$out"
}

if [ "$REPORT_ONLY" != 1 ]; then
  echo "eval: model=$MODEL skill=$SKILL_ID cases=${CASES[*]} variants=${VARIANT_LIST[*]} runs=$RUNS"
  echo "eval: engine=$ENGINE"
  echo "eval: results -> $RUN_DIR"
  for case_id in "${CASES[@]}"; do
    [ -f "$EVAL_DIR/cases/$case_id/case.json" ] || die "no such case: $case_id"
    for i in $(seq 1 "$RUNS"); do
      for variant in "${VARIANT_LIST[@]}"; do
        run_variant "$case_id" "$variant" "$i"
      done
    done
  done
fi

python3 "$EVAL_DIR/bin/aggregate.py" --run-dir "$RUN_DIR" --history "$HISTORY"
python3 "$EVAL_DIR/bin/report.py" --run-dir "$RUN_DIR" --history "$HISTORY" \
        --out "$RUN_DIR/report.html"
ln -sfn "$(basename "$RUN_DIR")/report.html" "$EVAL_DIR/results/latest-report.html"

# Cross-model view. The per-run report charts a single model; this puts every
# model that has ever run these cases side by side. Non-fatal: a comparison
# failure must not sink a run whose model calls have already been paid for.
# Written to a temp file and moved into place only on success: a half-written
# or stale page that still looks current is worse than an obviously missing one.
if python3 "$EVAL_DIR/bin/compare.py" --history "$HISTORY" \
        --results-dir "$EVAL_DIR/results" --out "$EVAL_DIR/results/.compare.html.tmp"; then
  mv "$EVAL_DIR/results/.compare.html.tmp" "$EVAL_DIR/results/compare.html"
else
  rm -f "$EVAL_DIR/results/.compare.html.tmp"
  echo "eval: WARNING compare.html generation failed; the existing page is from" >&2
  echo "      an earlier run and is now out of date (results themselves are intact)" >&2
fi

# Full history, archived regimes included, so the arc survives a re-base.
TL=(--history "$HISTORY")
[ -f "$EVAL_DIR/archive/history.jsonl" ] && TL+=(--history "$EVAL_DIR/archive/history.jsonl")
if python3 "$EVAL_DIR/bin/timeline.py" "${TL[@]}" \
        --out "$EVAL_DIR/results/.timeline.html.tmp"; then
  mv "$EVAL_DIR/results/.timeline.html.tmp" "$EVAL_DIR/results/timeline.html"
else
  rm -f "$EVAL_DIR/results/.timeline.html.tmp"
  echo "eval: WARNING timeline.html generation failed; the existing page is from" >&2
  echo "      an earlier run and is now out of date (results themselves are intact)" >&2
fi

echo "eval: report  -> $RUN_DIR/report.html"
echo "eval: compare -> $EVAL_DIR/results/compare.html"
echo "eval: timeline-> $EVAL_DIR/results/timeline.html"
if [ "$OPEN_REPORT" = 1 ]; then
  xdg-open "$RUN_DIR/report.html" >/dev/null 2>&1 &
fi
