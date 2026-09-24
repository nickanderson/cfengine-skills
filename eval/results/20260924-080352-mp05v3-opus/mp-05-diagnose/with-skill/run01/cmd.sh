#!/bin/sh
# Re-run this variant exactly as the harness did. A fresh jail is created;
# its path is printed at the end so the artifacts can be inspected.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../../../.." && pwd)
JAIL=$(mktemp -d "${TMPDIR:-/tmp}/cfeval-replay.XXXXXXXX")
mkdir -p "$JAIL/work" "$JAIL/config"
cp "$HOME/.claude/.credentials.json" "$JAIL/config/" 2>/dev/null || true
mkdir -p "$JAIL/config/skills"
cp -a "$REPO/mission-portal" "$JAIL/config/skills/mission-portal"
cp -a "$REPO/scripts" "$JAIL/config/skills/scripts"
export CFENGINE_SKILL_UPDATE_DISABLE=1
# mp-api.sh reads the password from a netrc built from $MP_URL/$MP_USER/$MP_PASSWORD
h=${MP_URL#*://}; h=${h%%[:/]*}
( umask 077; printf "machine %s login %s password %s\n" "$h" "$MP_USER" "$MP_PASSWORD" > "$JAIL/netrc" )
printf "url=%s\nnetrc=%s\ninsecure=1\n" "$MP_URL" "$JAIL/netrc" > "$JAIL/mission-portal.conf"
export MP_CONFIG="$JAIL/mission-portal.conf"
mkdir -p "$JAIL/out"
CLAUDE_CONFIG_DIR="$JAIL/config" "$REPO/eval/lib/console-claude.sh" \
  "$JAIL" "$JAIL/out" 900 "$HERE/prompt.txt" --image localhost/cfeval-console:9358ca44af52 -- \
  --model opus \
  --append-system-prompt "$(cat "$HERE/system-prompt.txt")" \
  --strict-mcp-config --dangerously-skip-permissions || true
echo "results: $JAIL/out"

echo "jail: $JAIL"
