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
cp -a "$REPO/cfengine-policy" "$JAIL/config/skills/cfengine-policy"
cp -a "$REPO/scripts" "$JAIL/config/skills/scripts"
export CFENGINE_SKILL_UPDATE_DISABLE=1
cd "$JAIL/work"
CLAUDE_CONFIG_DIR="$JAIL/config" claude \
  -p "$(cat "$HERE/prompt.txt")" \
  --model haiku --output-format json \
  --append-system-prompt "$(cat "$HERE/system-prompt.txt")" \
  --strict-mcp-config --no-session-persistence \
  --dangerously-skip-permissions
echo "jail: $JAIL"
