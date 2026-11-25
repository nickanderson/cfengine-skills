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

EVAL_DIR=${CFEVAL_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}

# Run from a private copy. bash reads a script as it executes, so editing this
# file while an eval runs -- even writing it back unchanged -- makes the
# running eval execute from a shifted offset: two runs on 2026-09-23 lost
# their aggregation that way. The copy pins what this run executes.
if [ -z "${CFEVAL_SNAPSHOT:-}" ]; then
  snap=$(mktemp "${TMPDIR:-/tmp}/run-eval.XXXXXX.sh")
  cp "${BASH_SOURCE[0]}" "$snap"
  CFEVAL_SNAPSHOT=$snap CFEVAL_DIR=$EVAL_DIR exec bash "$snap" "$@"
fi
trap 'rm -f "$CFEVAL_SNAPSHOT"' EXIT
REPO_DIR=$(cd "$EVAL_DIR/.." && pwd)
# Which skill a run measures comes from its cases (case.json "skill"); one run
# measures one skill. --skill picks the default case set when --case is absent.
SKILL_NAME=""
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
# console: interactive claude in a screen session with the prompt pasted in, as
# a user at a terminal runs it (lib/console-claude.sh). print: claude -p.
DRIVER=console
# Where a console session runs: a container built from container/Containerfile
# (default, tagged by the file's hash), or "none" for the workstation itself.
SESSION_IMAGE=auto
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
  --case ID          case to run (repeatable; default: every case for --skill)
  --skill NAME       skill whose cases run when --case is absent
                     (default: cfengine-policy)
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
                     (print driver only)
  --driver NAME      console (default): interactive claude in screen, prompt
                     pasted at the console; print: claude -p
  --session-image REF  container the console session runs in (default: built
                     from eval/container/Containerfile); "none" runs it on
                     this machine with this machine's tools
  --no-open          do not launch a browser for the report
  --report-only      regenerate report/history from existing results and exit
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --case)        CASES+=("$2"); shift 2 ;;
    --skill)       SKILL_NAME=$2; shift 2 ;;
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
    --driver)      DRIVER=$2; shift 2 ;;
    --session-image) SESSION_IMAGE=$2; shift 2 ;;
    --no-open)     OPEN_REPORT=0; shift ;;
    --report-only) REPORT_ONLY=1; shift ;;
    -h|--help)     usage; exit 0 ;;
    *)             die "unknown option: $1 (try --help)" ;;
  esac
done

command -v python3 >/dev/null || die "missing required tool: python3"
case "$DRIVER" in
  console) [ "$REPORT_ONLY" = 1 ] || command -v screen >/dev/null || die "missing required tool: screen (or use --driver print)"
           [ "$SAFE_PERMS" = 1 ] && die "--safe-perms needs --driver print" ;;
  print) ;;
  *) die "unknown driver: $DRIVER (console or print)" ;;
esac

# Started from inside Claude Code, this shell carries that session's identity
# (CLAUDECODE, CLAUDE_CODE_CHILD_SESSION, CLAUDE_CODE_SESSION_ID, a messaging
# socket and token), and every claude it starts runs as that session's child
# -- one that, among other things, writes no transcript. Drop it all.
while IFS= read -r v; do unset "$v"; done < <(compgen -e | grep -E '^CLAUDE')

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
# The console session's container. Built on the grader's CFEngine image, so
# the model validates with the same CFEngine the grader does.
if [ "$REPORT_ONLY" != 1 ] && [ "$DRIVER" = console ] && [ "$SESSION_IMAGE" != none ]; then
  command -v podman >/dev/null || die "missing required tool: podman (or --session-image none)"
  if [ "$SESSION_IMAGE" = auto ]; then
    [ -n "$IMAGE" ] || die "the session image builds on --image; use --session-image none with --no-container"
    SESSION_IMAGE="localhost/cfeval-console:$( { cat "$EVAL_DIR/container/Containerfile"; echo "$IMAGE"; } | sha256sum | cut -c1-12)"
    if ! podman image exists "$SESSION_IMAGE"; then
      echo "run-eval: building $SESSION_IMAGE"
      podman build -q --build-arg "BASE=$IMAGE" -t "$SESSION_IMAGE" "$EVAL_DIR/container" >/dev/null \
        || die "could not build $SESSION_IMAGE"
    fi
  fi
  podman image exists "$SESSION_IMAGE" || die "no such image: $SESSION_IMAGE"
fi
[ "$DRIVER" = console ] || SESSION_IMAGE=none

# case.json field, with a default for cases written before the field existed.
case_field() {
  python3 -c 'import json,sys; c=json.load(open(sys.argv[1]))
v=c.get(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else "")
print("\n".join(v) if isinstance(v, list) else v)' "$EVAL_DIR/cases/$1/case.json" "${@:2}"
}

if [ ${#CASES[@]} -eq 0 ]; then
  : "${SKILL_NAME:=cfengine-policy}"
  while IFS= read -r d; do
    c=$(basename "$d")
    [ -f "$d/case.json" ] && [ "$(case_field "$c" skill cfengine-policy)" = "$SKILL_NAME" ] || continue
    if [ -n "$(case_field "$c" disabled)" ]; then
      echo "run-eval: skipping $c (disabled: $(case_field "$c" disabled))" >&2
      continue
    fi
    CASES+=("$c")
  done < <(find "$EVAL_DIR/cases" -mindepth 1 -maxdepth 1 -type d | sort)
fi
[ ${#CASES[@]} -gt 0 ] || die "no cases found under $EVAL_DIR/cases${SKILL_NAME:+ for skill $SKILL_NAME}"
for c in "${CASES[@]}"; do
  [ -f "$EVAL_DIR/cases/$c/case.json" ] || die "no such case: $c"
  s=$(case_field "$c" skill cfengine-policy)
  [ -z "$SKILL_NAME" ] && SKILL_NAME=$s
  # run-info.json, the snapshot and history rows all stamp a single skill.
  [ "$s" = "$SKILL_NAME" ] || die "case $c is for skill $s, not $SKILL_NAME; run skills separately"
done
SKILL_DIR="$REPO_DIR/$SKILL_NAME"
SKILL_MD="$SKILL_DIR/SKILL.md"
# A baseline needs no skill: that is how a new skill's eval gets written first.
if [ ! -f "$SKILL_MD" ]; then
  [ "$VARIANTS" = no-skill ] || die "skill not found: $SKILL_MD (a --variant no-skill baseline can run without it)"
  echo "run-eval: $SKILL_MD does not exist yet; running the baseline only" >&2
fi
skill_sha() { if [ -f "$SKILL_MD" ]; then sha256sum "$SKILL_MD" | cut -d' ' -f1; else echo none; fi; }

case "$VARIANTS" in
  both)       VARIANT_LIST=(no-skill with-skill) ;;
  with-skill) VARIANT_LIST=(with-skill) ;;
  no-skill)   VARIANT_LIST=(no-skill) ;;
  *)          die "--variant must be both, with-skill or no-skill" ;;
esac

# --- skill identity: what this run is measuring --------------------------------
SKILL_COMMIT=$(git -C "$REPO_DIR" log -1 --format=%H -- "$SKILL_NAME/SKILL.md" 2>/dev/null || true)
[ -n "$SKILL_COMMIT" ] || SKILL_COMMIT="uncommitted"
if git -C "$REPO_DIR" status --porcelain -- "$SKILL_NAME/SKILL.md" 2>/dev/null | grep -q .; then
  SKILL_DIRTY=true
else
  SKILL_DIRTY=false
fi
SKILL_SHA=$(skill_sha)
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
  "driver": "$DRIVER",
  "session_image": "$SESSION_IMAGE",
  "session_image_id": "$( [ "$SESSION_IMAGE" = none ] || podman image inspect --format '{{.Id}}' "$SESSION_IMAGE" 2>/dev/null)",
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
    "path": "$SKILL_NAME/SKILL.md",
    "commit": "$SKILL_COMMIT",
    "dirty": $SKILL_DIRTY,
    "sha256": "$SKILL_SHA",
    "id": "$SKILL_ID",
    "bytes": $(cat "$SKILL_MD" 2>/dev/null | wc -c)
  }
}
JSON
  [ -f "$SKILL_MD" ] && cp "$SKILL_MD" "$RUN_DIR/SKILL.md.snapshot"
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
  sysprompt=$(cat "$EVAL_DIR/$(case_field "$case_id" system_prompt lib/base-system-prompt.txt)")
  if [ "$variant" = with-skill ]; then
    # Install into the jail's skills directory, flat -- Claude Code discovers
    # skills/<name>/SKILL.md and does not recurse, so a nested copy is invisible.
    # Copied rather than symlinked into the repo: a symlink would let the model
    # walk up into eval/results and read every other run's answer.
    mkdir -p "$jail/config/skills"
    cp -a "$SKILL_DIR" "$jail/config/skills/$SKILL_NAME"
    # The skill resolves its helpers as ${CLAUDE_SKILL_DIR}/../scripts.
    cp -a "$REPO_DIR/scripts" "$jail/config/skills/scripts"
    sysprompt="$sysprompt"$'\n'"$(sed "s/cfengine-policy/$SKILL_NAME/g" "$EVAL_DIR/lib/skill-system-prompt.txt")"
  fi

  # A user of the mission-portal skill keeps the password in a netrc that the
  # skill's mp-api.sh reads, so the with-skill side gets one too. It sits in
  # the jail root, outside work/, so it is never copied into the results.
  local -a skill_env=()
  if [ "$variant" = with-skill ] && [ "$SKILL_NAME" = mission-portal ] && [ -n "${MP_URL:-}" ]; then
    local mp_host=${MP_URL#*://}; mp_host=${mp_host%%[:/]*}
    ( umask 077; printf 'machine %s login %s password %s\n' "$mp_host" "$MP_USER" "$MP_PASSWORD" > "$jail/netrc" )
    # A config file, not MP_NETRC/MP_INSECURE in the environment: the model's
    # own shell inherits the environment, and a script it tests with
    # MP_INSECURE=1 set then fails under the grader, which does not set it.
    # That happened -- 2 of 3 mp-03 runs scored 15 for it. insecure=1 because
    # the eval hub is disposable and self-signed.
    printf 'url=%s\nnetrc=%s\ninsecure=1\n' "$MP_URL" "$jail/netrc" > "$jail/mission-portal.conf"
    skill_env=(MP_CONFIG="$jail/mission-portal.conf")
  fi

  # --disable-slash-commands is deliberately absent: it also makes installed
  # skills unavailable, which silently turned the with-skill side into a second
  # baseline. A fresh config dir has no custom commands to guard against anyway.
  local -a perms=(--dangerously-skip-permissions)
  [ "$SAFE_PERMS" = 1 ] && perms=(--permission-mode acceptEdits --permission-prompts none)

  local prompt
  prompt=$(cat "$case_dir/prompt.txt")
  SKILL_SHA_BEFORE=$(skill_sha)

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
      printf 'cp -a "$REPO/%s" "$JAIL/config/skills/%s"\n' "$SKILL_NAME" "$SKILL_NAME"
      printf 'cp -a "$REPO/scripts" "$JAIL/config/skills/scripts"\n'
      printf 'export CFENGINE_SKILL_UPDATE_DISABLE=1\n'
      if [ "$SKILL_NAME" = mission-portal ]; then
        printf '# mp-api.sh reads the password from a netrc built from $MP_URL/$MP_USER/$MP_PASSWORD\n'
        printf 'h=${MP_URL#*://}; h=${h%%%%[:/]*}\n'
        printf '( umask 077; printf "machine %%s login %%s password %%s\\n" "$h" "$MP_USER" "$MP_PASSWORD" > "$JAIL/netrc" )\n'
        printf 'printf "url=%%s\\nnetrc=%%s\\ninsecure=1\\n" "$MP_URL" "$JAIL/netrc" > "$JAIL/mission-portal.conf"\n'
        printf 'export MP_CONFIG="$JAIL/mission-portal.conf"\n'
      fi
    fi
    if [ "$DRIVER" = console ]; then
      printf 'mkdir -p "$JAIL/out"\n'
      printf 'CLAUDE_CONFIG_DIR="$JAIL/config" "$REPO/eval/lib/console-claude.sh" \\\n'
      printf '  "$JAIL" "$JAIL/out" %s "$HERE/prompt.txt" %s -- \\\n' "$TIMEOUT" \
        "$( [ "$SESSION_IMAGE" = none ] || echo "--image $SESSION_IMAGE" )"
      printf '  --model %s \\\n' "$MODEL"
      printf '  --append-system-prompt "$(cat \"$HERE/system-prompt.txt\")" \\\n'
      printf '  --strict-mcp-config %s || true\n' "${perms[*]}"
      printf 'echo "results: $JAIL/out"\n'
    else
      printf 'cd "$JAIL/work"\n'
      printf 'CLAUDE_CONFIG_DIR="$JAIL/config" claude \\\n'
      printf '  -p "$(cat \"$HERE/prompt.txt\")" \\\n'
      printf '  --model %s --output-format json \\\n' "$MODEL"
      printf '  --append-system-prompt "$(cat \"$HERE/system-prompt.txt\")" \\\n'
      printf '  --strict-mcp-config --no-session-persistence \\\n'
      printf '  %s' "${perms[*]}"
    fi
    printf '\necho "jail: $JAIL"\n'
  } > "$out/cmd.sh"
  chmod +x "$out/cmd.sh"
  cp "$case_dir/prompt.txt" "$out/prompt.txt"

  # A case whose run consumes hub state (mp-06 deletes its target) names a
  # script that restores it before every invocation.
  local pre_run
  pre_run=$(case_field "$case_id" pre_run)
  if [ -n "$pre_run" ]; then
    mkdir -p "$out"
    local -a pr
    read -r -a pr <<< "$pre_run"   # "<script relative to eval/> [args...]"
    bash "$EVAL_DIR/${pr[0]}" "${pr[@]:1}" > "$out/pre-run.log" 2>&1 \
      || die "pre_run failed for $case_id (see $out/pre-run.log)"
  fi

  echo "  -> $case_id/$variant run$idx (jail: $jail, driver: $DRIVER, session: $SESSION_IMAGE)"
  local rc=0
  if [ "$DRIVER" = console ]; then
    # Writes raw.json in the -p shape, from the session transcript, plus
    # console.log, screen-final.txt and transcript.jsonl. The outer timeout
    # only backstops the driver's own.
    # In the container the session sees only what is named here: the case's
    # env (MP_URL, ...), the skill's config, and the docs checkout read-only.
    local -a sess=()
    if [ "$SESSION_IMAGE" != none ]; then
      sess=(--image "$SESSION_IMAGE" --env CFENGINE_SKILL_UPDATE_DISABLE --env CFENGINE_DOCS_DIR)
      [ -d "$DOCS_DIR" ] && sess+=(--ro "$DOCS_DIR")
      local e
      for e in "${skill_env[@]}"; do sess+=(--env "${e%%=*}"); done
      while IFS= read -r e; do
        [ -n "$e" ] && [ "$e" != MP_VAGRANT_DIR ] && sess+=(--env "$e")
      done < <(case_field "$case_id" env)
    fi
    CLAUDE_CONFIG_DIR="$jail/config" CFENGINE_SKILL_UPDATE_DISABLE=1 CFENGINE_DOCS_DIR="$DOCS_DIR" \
      env -u MP_VAGRANT_DIR "${skill_env[@]}" timeout $((TIMEOUT + 120)) \
      "$EVAL_DIR/lib/console-claude.sh" "$jail" "$out" "$TIMEOUT" "$case_dir/prompt.txt" "${sess[@]}" -- \
      --model "$MODEL" \
      --append-system-prompt "$sysprompt" \
      --strict-mcp-config \
      "${perms[@]}" 2> "$out/stderr.log" 8>&- || rc=$?
  else
    ( cd "$jail/work" && CLAUDE_CONFIG_DIR="$jail/config" \
        CFENGINE_SKILL_UPDATE_DISABLE=1 env -u MP_VAGRANT_DIR "${skill_env[@]}" timeout "$TIMEOUT" claude \
        -p "$prompt" \
        --model "$MODEL" \
        --output-format json \
        --append-system-prompt "$sysprompt" \
        --strict-mcp-config \
        --no-session-persistence \
        "${perms[@]}" ) > "$out/raw.json" 2> "$out/stderr.log" 8>&- || rc=$?
  fi

  SKILL_SHA_AFTER=$(skill_sha)

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
           ("duration_ms", "duration_api_ms", "num_turns", "total_cost_usd", "is_error", "subtype",
            "usage", "driver")}
except ValueError:
    cli = {"parse_error": True}
# Written verbatim; bin/scrub.py redacts this whole directory after analysis.
(out / "response.md").write_text(text)
(out / "system-prompt.txt").write_text(os.environ.get("SYSPROMPT", ""))
meta = {"variant": variant, "run": idx, "model": model, "exit_code": rc, "cli": cli,
        "skill_sha256": sha_before}
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

  # And one that adds hub state (mp-03's clone fleet) names a script that
  # removes it once graded, so it cannot leak into the next case's fixtures.
  # Not fatal: the run is already paid for, but say so loudly.
  local post_run
  post_run=$(case_field "$case_id" post_run)
  if [ -n "$post_run" ]; then
    local -a po
    read -r -a po <<< "$post_run"
    bash "$EVAL_DIR/${po[0]}" "${po[@]:1}" > "$out/post-run.log" 2>&1 \
      || echo "run-eval: WARNING post_run failed for $case_id (see $out/post-run.log); the hub may need lib/mp-setup-hub.sh" >&2
  fi

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
  # One hub, shared by every live-service run. Read-only cases share it; a
  # case marked "exclusive" (mp-06, which deletes hosts) takes it alone,
  # waiting for other runs to finish and holding new ones off, so whatever a
  # careless agent does cannot spoil another run's fixtures mid-run. The lock
  # is held until this run exits. The model's session is started with fd 8
  # closed (8>&-): screen and podman outlive their parent, and one that
  # inherited the fd would hold the lock after a crashed run, blocking every
  # later run against this hub.
  hub_mode=""
  for c in "${CASES[@]}"; do
    [ "$(case_field "$c" grader)" = mission-portal ] || continue
    [ -n "$hub_mode" ] || hub_mode=-s
    [ -n "$(case_field "$c" exclusive)" ] && hub_mode=-x
  done
  if [ -n "$hub_mode" ]; then
    hub_host=${MP_URL:-hub}; hub_host=${hub_host#*://}; hub_host=${hub_host%%[:/]*}
    exec 8>"${TMPDIR:-/tmp}/cfeval-hub-$hub_host.lock"
    if ! flock -n $hub_mode 8; then
      echo "eval: waiting for the hub lock ($hub_host; $([ $hub_mode = -x ] && echo "exclusive: other hub runs must finish" || echo "an exclusive run holds it"))"
      flock $hub_mode 8
    fi
  fi
  for case_id in "${CASES[@]}"; do
    [ -f "$EVAL_DIR/cases/$case_id/case.json" ] || die "no such case: $case_id"
    # Live-service cases: the hub must already be in the state the case grades
    # against, and the credentials handed to the model must not be committed.
    if [ "$(case_field "$case_id" grader)" = mission-portal ]; then
      # A case whose state comes from its pre_run (mp-03's clone fleet) has
      # none of it yet: build it once so preflight checks what the case will
      # run against. run_variant rebuilds it before every invocation.
      pre_run=$(case_field "$case_id" pre_run)
      if [ -n "$pre_run" ]; then
        read -r -a pr <<< "$pre_run"
        bash "$EVAL_DIR/${pr[0]}" "${pr[@]:1}" > "$RUN_DIR/pre-run-$case_id.log" 2>&1 \
          || die "pre_run failed for $case_id (see $RUN_DIR/pre-run-$case_id.log)"
      fi
      python3 "$EVAL_DIR/bin/grade_mp.py" --preflight \
          --case-file "$EVAL_DIR/cases/$case_id/case.json" || {
        # Leave the hub as it was: undo what pre_run just added.
        post_run=$(case_field "$case_id" post_run)
        if [ -n "$post_run" ]; then
          read -r -a po <<< "$post_run"
          bash "$EVAL_DIR/${po[0]}" "${po[@]:1}" >> "$RUN_DIR/pre-run-$case_id.log" 2>&1 || true
        fi
        die "preflight failed"
      }
    fi
    CFEVAL_REDACT=""
    while IFS= read -r v; do
      [ -n "$v" ] && CFEVAL_REDACT+="${!v}"$'\n'
    done < <(case_field "$case_id" secret_env)
    export CFEVAL_REDACT
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
