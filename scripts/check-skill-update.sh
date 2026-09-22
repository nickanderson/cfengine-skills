#!/usr/bin/env bash
# Report whether this skill's own checkout is behind upstream.
#
# Called from the skill's dynamic context block, so stdout enters the model's
# context. That budget is the user's attention: this script stays completely
# silent unless there is something for the user to decide.
#
# It never changes anything. Updating is a git pull against the user's own
# checkout, which is their call -- the script only surfaces the fact, and the
# model asks. Deciding for them is how a skill quietly rewrites itself
# underneath someone.
#
# Never exits non-zero and never blocks for long: a skill that fails to render
# because the network is down is worse than a skill that is a week stale.

# Deliberately no -e: a failed fetch must not abort skill rendering.
set -uo pipefail

[[ -n "${CFENGINE_SKILL_UPDATE_DISABLE:-}" ]] && exit 0

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SKILL_SUBDIR="${CFENGINE_SKILL_SUBDIR:-cfengine-policy}"

STATE_FILE="${CFENGINE_SKILL_UPDATE_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/cfengine-skills/update-check}"
FETCH_INTERVAL_DAYS="${CFENGINE_SKILL_UPDATE_INTERVAL_DAYS:-7}"
NOTICE_INTERVAL_DAYS="${CFENGINE_SKILL_UPDATE_NOTICE_DAYS:-7}"
FETCH_TIMEOUT="${CFENGINE_SKILL_UPDATE_TIMEOUT:-10}"

now=$(date +%s)

# A copied-in skill has no checkout to update; nothing to say.
REPO=$(git -C "$SCRIPT_DIR" rev-parse --show-toplevel 2>/dev/null) || exit 0
[[ -n "$REPO" ]] || exit 0

SKILL_PATH="$REPO/$SKILL_SUBDIR"
[[ -d "$SKILL_PATH" ]] || exit 0

# --- state -------------------------------------------------------------
last_fetch=0 last_notice=0 last_notice_sha=""
if [[ -f "$STATE_FILE" ]]; then
    while IFS='=' read -r k v; do
        case "$k" in
            last_fetch) last_fetch=$v ;;
            last_notice) last_notice=$v ;;
            last_notice_sha) last_notice_sha=$v ;;
        esac
    done < "$STATE_FILE"
fi

write_state() {
    mkdir -p "$(dirname "$STATE_FILE")" 2>/dev/null || return 0
    printf 'last_fetch=%s\nlast_notice=%s\nlast_notice_sha=%s\n' \
        "$1" "$2" "$3" > "$STATE_FILE" 2>/dev/null || true
}

age_days() { echo $(( (now - ${1:-0}) / 86400 )); }

# --- refresh remote state, rarely --------------------------------------
if (( $(age_days "$last_fetch") >= FETCH_INTERVAL_DAYS )); then
    timeout_cmd=()
    command -v timeout >/dev/null 2>&1 && timeout_cmd=(timeout "$FETCH_TIMEOUT")
    GIT_TERMINAL_PROMPT=0 "${timeout_cmd[@]}" \
        git -C "$REPO" fetch --quiet origin >/dev/null 2>&1
    # Record the attempt either way; a machine that is offline for a month
    # should not retry on every single skill load.
    last_fetch=$now
    write_state "$last_fetch" "$last_notice" "$last_notice_sha"
fi

# --- how far behind, counting only commits that touch the skill --------
BRANCH=$(git -C "$REPO" rev-parse --abbrev-ref HEAD 2>/dev/null)
UPSTREAM=$(git -C "$REPO" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)
if [[ -z "$UPSTREAM" ]]; then
    UPSTREAM="origin/$BRANCH"
    git -C "$REPO" rev-parse --verify --quiet "$UPSTREAM" >/dev/null 2>&1 || exit 0
fi

behind=$(git -C "$REPO" rev-list --count "HEAD..$UPSTREAM" -- "$SKILL_PATH" 2>/dev/null) || exit 0
[[ -n "$behind" ]] || exit 0

# Uncommitted local edits to the skill: an update would not apply cleanly.
dirty=""
if ! git -C "$REPO" diff --quiet -- "$SKILL_PATH" 2>/dev/null ||
   ! git -C "$REPO" diff --cached --quiet -- "$SKILL_PATH" 2>/dev/null; then
    dirty=1
fi

(( behind == 0 )) && [[ -z "$dirty" ]] && exit 0

# --- notice throttle ---------------------------------------------------
# Re-notify when upstream moves, otherwise at most once per interval. Being
# told daily about an update you have already declined is how a skill teaches
# people to ignore it.
upstream_sha=$(git -C "$REPO" rev-parse --short "$UPSTREAM" 2>/dev/null)
if [[ "$upstream_sha" == "$last_notice_sha" ]] &&
   (( $(age_days "$last_notice") < NOTICE_INTERVAL_DAYS )); then
    exit 0
fi

if (( behind > 0 )); then
    plural=s; (( behind == 1 )) && plural=""
    echo "SKILL UPDATE AVAILABLE: $SKILL_SUBDIR is $behind commit$plural behind $UPSTREAM."
    if [[ -n "$dirty" ]]; then
        echo "The local skill also has uncommitted changes, so a pull will not apply cleanly."
        echo "Tell the user both facts and let them decide how to reconcile; do not discard their edits."
    else
        echo "Tell the user an update is available and ask whether to apply it."
        echo "If they agree, run: git -C $REPO pull --ff-only"
        echo "Do not update without their approval."
    fi
elif [[ -n "$dirty" ]]; then
    echo "NOTE: $SKILL_SUBDIR has uncommitted local changes; the guidance below may not match upstream."
fi

write_state "$last_fetch" "$now" "$upstream_sha"
exit 0
