#!/bin/sh
# Re-run this variant exactly as the harness did. A fresh jail is created;
# its path is printed at the end so the artifacts can be inspected.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../../../../.." && pwd)
JAIL=$(mktemp -d "${TMPDIR:-/tmp}/cfeval-replay.XXXXXXXX")
mkdir -p "$JAIL/work" "$JAIL/config"
cp "$HOME/.claude/.credentials.json" "$JAIL/config/" 2>/dev/null || true
mkdir -p "$JAIL/out"
CLAUDE_CONFIG_DIR="$JAIL/config" "$REPO/eval/lib/console-claude.sh" \
  "$JAIL" "$JAIL/out" 900 "$HERE/prompt.txt" --image localhost/cfeval-console:9358ca44af52 -- \
  --model sonnet \
  --append-system-prompt "$(cat "$HERE/system-prompt.txt")" \
  --strict-mcp-config --dangerously-skip-permissions || true
echo "results: $JAIL/out"

echo "jail: $JAIL"
