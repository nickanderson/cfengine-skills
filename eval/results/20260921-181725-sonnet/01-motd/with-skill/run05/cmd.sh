#!/bin/sh
# Re-run this arm exactly as the harness did. A fresh jail is created;
# its path is printed at the end so the artifacts can be inspected.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
SKILL_DIR=$(cd "$HERE/../../../../../../cfengine-policy" && pwd)
JAIL=$(mktemp -d "${TMPDIR:-/tmp}/cfeval-replay.XXXXXXXX")
mkdir -p "$JAIL/work" "$JAIL/config"
cp "$HOME/.claude/.credentials.json" "$JAIL/config/" 2>/dev/null || true
cd "$JAIL/work"
CLAUDE_CONFIG_DIR="$JAIL/config" claude \
  -p "$(cat "$HERE/prompt.txt")" \
  --model sonnet --output-format json \
  --append-system-prompt "$(cat "$HERE/system-prompt.txt")" \
  --disable-slash-commands --strict-mcp-config --no-session-persistence \
  --dangerously-skip-permissions \
  --add-dir "$SKILL_DIR"
echo "jail: $JAIL"
