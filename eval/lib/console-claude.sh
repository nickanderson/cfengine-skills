#!/usr/bin/env bash
# Drive one interactive Claude Code session the way a user at a console does:
# start `claude` in a detached screen session, wait for its prompt, paste the
# prompt in, press Enter, wait for the turn to end, then /exit.
#
#   console-claude.sh <jail> <out> <timeout-secs> <prompt-file> \
#       [--image REF] [--env NAME]... [--ro PATH]... -- <claude args...>
#
# <jail>/config is the session's CLAUDE_CONFIG_DIR and <jail>/work its cwd.
#
# With --image, claude runs in that container (eval/container/Containerfile),
# not on the workstation: the jail is mounted at its own path, so paths in the
# Stop hook and the transcript mean the same inside and out; the host's claude
# binary is mounted read-only; each --ro PATH is mounted read-only at its own
# path; and the session sees only HOME=<jail>/home, TERM, CLAUDE_CONFIG_DIR
# and the --env NAMEs, with their values from this environment. Without
# --image the caller's environment passes through. Writes to <out>:
#
#   console.log       everything the terminal showed (screen's log)
#   screen-final.txt  the last screen as the user saw it
#   transcript.jsonl  the session transcript, for the answer, turns and usage
#   raw.json          what `claude -p --output-format json` would have printed,
#                     rebuilt from the transcript; total_cost_usd and
#                     duration_api_ms are what /cost showed at the end
#
# A fresh config dir starts on first-run screens (theme, folder trust, the
# bypass-permissions warning) that no returning user sees, so they are
# pre-answered. The turn's end comes from a Stop hook rather than from
# scraping the screen. Exit status: 0 done, 124 timed out, 1 setup failure.
set -euo pipefail
jail=$1 out=$2 timeout=$3 prompt_file=$4
shift 4
image="" envs=() ros=()
while [ $# -gt 0 ] && [ "$1" != -- ]; do
  case "$1" in
    --image) image=$2; shift 2 ;;
    --env)   envs+=("$2"); shift 2 ;;
    --ro)    ros+=("$2"); shift 2 ;;
    *) echo "console-claude: unknown option $1" >&2; exit 1 ;;
  esac
done
[ "${1-}" = -- ] && shift

cfg=$jail/config work=$jail/work
name=cfeval-$$-$RANDOM
ver=$(claude --version 2>/dev/null | awk '{print $1}')

python3 - "$cfg" "$work" "$jail" "$ver" <<'PY'
import json, sys
from pathlib import Path
cfg, work, jail, ver = Path(sys.argv[1]), sys.argv[2], sys.argv[3], sys.argv[4]
g = cfg / ".claude.json"
d = json.loads(g.read_text()) if g.exists() else {}
d.update({"hasCompletedOnboarding": True, "lastOnboardingVersion": ver,
          "lastReleaseNotesSeen": ver, "theme": "dark", "numStartups": 1})
d.setdefault("projects", {}).setdefault(work, {})["hasTrustDialogAccepted"] = True
g.write_text(json.dumps(d, indent=2))
s = cfg / "settings.json"
d = json.loads(s.read_text()) if s.exists() else {}
d["skipDangerousModePermissionPrompt"] = True
d.setdefault("hooks", {})["Stop"] = [
    {"hooks": [{"type": "command", "command": "cat > '%s/stop.json'" % jail}]}]
s.write_text(json.dumps(d, indent=2))
PY

# screen runs the command through a shell; quote every argument into it.
q() { local a r=""; for a in "$@"; do r+=" $(printf %q "$a")"; done; printf '%s' "$r"; }
if [ -n "$image" ]; then
  # Its own temp dir: mounting the jail creates the jail's parents as root,
  # and claude refuses a /tmp/claude-<uid> it does not own.
  mkdir -p "$jail/home" "$jail/tmp"
  run=(podman run --rm -it --name "$name" --userns=keep-id
       -v "$jail:$jail" -v "$(readlink -f "$(command -v claude)"):/usr/local/bin/claude:ro"
       -w "$work" -e TERM=xterm-256color -e "HOME=$jail/home" -e "CLAUDE_CONFIG_DIR=$cfg"
       -e "CLAUDE_CODE_TMPDIR=$jail/tmp")
  for p in "${ros[@]}"; do run+=(-v "$p:$p:ro"); done
  for e in "${envs[@]}"; do run+=(-e "$e"); done
  cmd="exec$(q "${run[@]}" "$image" claude "$@")"
else
  cmd="cd $(printf %q "$work") && exec$(q claude "$@")"
fi
rm -f "$jail/stop.json"
# A harness started from inside Claude Code passes that session's identity on
# (CLAUDECODE, CLAUDE_CODE_CHILD_SESSION, CLAUDE_CODE_SESSION_ID, its messaging
# socket and token): the nested claude then runs as a child of it and writes
# no transcript of its own. A user's console has none of these.
while IFS= read -r v; do
  [ "$v" = CLAUDE_CONFIG_DIR ] || unset "$v"
done < <(compgen -e | grep -E '^CLAUDE')
screen -L -Logfile "$out/console.log" -dmS "$name" bash -c "$cmd"
trap 'screen -S "$name" -X quit >/dev/null 2>&1 || true
      [ -z "$image" ] || podman rm -f "$name" >/dev/null 2>&1 || true' EXIT

snap() { screen -S "$name" -X hardcopy "$out/screen-final.txt" 2>/dev/null; cat "$out/screen-final.txt" 2>/dev/null; }
alive() { screen -ls "$name" 2>/dev/null | grep -q "[.]$name[[:space:]]"; }

# Ready when the input box is drawn and no first-run dialog is up.
deadline=$((SECONDS + 60))
until snap | grep -q '? for shortcuts\|bypass permissions on'; do
  alive || { echo "console-claude: claude exited before its prompt appeared" >&2; exit 1; }
  [ $SECONDS -lt $deadline ] || { echo "console-claude: no prompt after 60s; see $out/screen-final.txt" >&2; exit 1; }
  sleep 1
done

# Bracketed paste, as a terminal sends it when a user pastes: the prompt's
# newlines stay newlines instead of submitting it line by line.
{ printf '\033[200~'; cat "$prompt_file"; printf '\033[201~'; } > "$jail/paste"
screen -S "$name" -X readreg p "$jail/paste"
screen -S "$name" -X paste p
sleep 1
screen -S "$name" -X stuff $'\r'
start_ms=$(date +%s%3N)

rc=0
deadline=$((SECONDS + timeout))
until [ -s "$jail/stop.json" ]; do
  alive || { echo "console-claude: claude exited mid-turn" >&2; rc=1; break; }
  [ $SECONDS -lt $deadline ] || { rc=124; break; }
  sleep 2
done
end_ms=$(date +%s%3N)
snap >/dev/null

# Cost the way a user reads it: /cost, then Esc to close the pane.
if [ "$rc" = 0 ]; then
  screen -S "$name" -X stuff $'/cost\r' 2>/dev/null || true
  for _ in $(seq 1 15); do
    sed 's/\x1b\[[0-9;?>]*[a-zA-Z]//g' "$out/console.log" 2>/dev/null | grep -aq 'Total cost:' && break
    sleep 1
  done
  screen -S "$name" -X stuff $'\033' 2>/dev/null || true
  sleep 1
fi
screen -S "$name" -X stuff $'/exit\r' 2>/dev/null || true
for _ in $(seq 1 15); do alive || break; sleep 1; done

python3 - "$jail" "$out" "$rc" "$((end_ms - start_ms))" <<'PY'
import json, sys, shutil
from pathlib import Path
jail, out, rc, dur = Path(sys.argv[1]), Path(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
tp = None
if (jail / "stop.json").exists():
    tp = json.loads((jail / "stop.json").read_text()).get("transcript_path")
if not tp:  # timed out or died: the newest transcript in the jail
    c = sorted((jail / "config" / "projects").glob("*/*.jsonl"), key=lambda p: p.stat().st_mtime)
    tp = str(c[-1]) if c else None
res = {"type": "result", "subtype": "success" if rc == 0 else ("error_timeout" if rc == 124 else "error"),
       "is_error": rc != 0, "duration_ms": dur, "duration_api_ms": None, "num_turns": 0,
       "result": "", "total_cost_usd": None, "usage": {}, "driver": "console"}
if tp and Path(tp).exists():
    shutil.copy(tp, out / "transcript.jsonl")
    usage, last_text, seen = {}, "", set()
    for line in Path(tp).read_text().splitlines():
        try:
            e = json.loads(line)
        except ValueError:
            continue
        m = e.get("message") or {}
        if e.get("type") != "assistant" or m.get("role") != "assistant":
            continue
        # One API response is written as several entries (one per content
        # block) sharing its id; count and bill it once.
        mid = m.get("id")
        if mid not in seen:
            seen.add(mid)
            res["num_turns"] += 1
            for k, v in (m.get("usage") or {}).items():
                if isinstance(v, (int, float)):
                    usage[k] = usage.get(k, 0) + v
        text = "".join(b.get("text", "") for b in m.get("content") or [] if b.get("type") == "text")
        if text.strip():
            last_text = text
    res["result"], res["usage"] = last_text, usage
# /cost's pane, from the console log with the escape sequences stripped.
import re
log = re.sub(r"\x1b\[[0-9;?>]*[a-zA-Z]|\x1b\][^\x07]*\x07", "", (out / "console.log").read_text(errors="replace")) \
    if (out / "console.log").exists() else ""
m = re.findall(r"Total cost:\s*\$([0-9.]+)", log)
if m:
    res["total_cost_usd"] = float(m[-1])
m = re.findall(r"Total duration \(API\):\s*((?:\d+(?:\.\d+)?[hms]\s*)+)", log)
if m:
    res["duration_api_ms"] = int(sum(float(n) * {"h": 3600, "m": 60, "s": 1}[u]
                                     for n, u in re.findall(r"(\d+(?:\.\d+)?)([hms])", m[-1])) * 1000)
(out / "raw.json").write_text(json.dumps(res, indent=2))
PY
exit $rc
