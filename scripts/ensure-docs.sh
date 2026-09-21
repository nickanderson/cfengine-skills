#!/usr/bin/env bash
# Ensure CFEngine documentation is cloned and version-matched.
# Called from skill dynamic context blocks. stdout enters skill context.
set -euo pipefail

DOCS_DIR="${CFENGINE_DOCS_DIR:-$HOME/.local/share/cfengine/docs}"
MAX_AGE_DAYS=7

# Detect CFEngine version
if command -v cf-agent >/dev/null 2>&1; then
    CF_VERSION=$(cf-agent -V 2>/dev/null | grep -oP '\d+\.\d+' | head -1)
else
    CF_VERSION=""
fi

if [[ -n "$CF_VERSION" ]]; then
    BRANCH="$CF_VERSION"
else
    BRANCH="master"
    echo "WARNING: cf-agent not found. Using master branch." >&2
fi

# Clone if missing
if [[ ! -d "$DOCS_DIR/.git" ]]; then
    echo "Cloning CFEngine documentation (branch $BRANCH)..." >&2
    git clone --branch "$BRANCH" --depth 1 \
        https://github.com/cfengine/documentation.git "$DOCS_DIR" 2>&1 >&2
fi

# Switch branch if version changed
CURRENT_BRANCH=$(git -C "$DOCS_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [[ "$CURRENT_BRANCH" != "$BRANCH" && "$BRANCH" != "master" ]]; then
    echo "Switching docs from $CURRENT_BRANCH to $BRANCH..." >&2
    git -C "$DOCS_DIR" fetch --depth 1 origin "$BRANCH" 2>&1 >&2
    git -C "$DOCS_DIR" checkout "$BRANCH" 2>&1 >&2 || \
        git -C "$DOCS_DIR" checkout -b "$BRANCH" "origin/$BRANCH" 2>&1 >&2
fi

# Pull if stale
if [[ -d "$DOCS_DIR/.git" ]]; then
    LAST_FETCH=$(stat -c %Y "$DOCS_DIR/.git/FETCH_HEAD" 2>/dev/null || echo 0)
    AGE_DAYS=$(( ($(date +%s) - LAST_FETCH) / 86400 ))
    if (( AGE_DAYS >= MAX_AGE_DAYS )); then
        echo "Docs checkout is ${AGE_DAYS}d old, updating..." >&2
        git -C "$DOCS_DIR" pull --ff-only 2>&1 >&2 || true
    fi
fi

# Toolchain check
_missing=()
command -v cf-agent >/dev/null 2>&1    || _missing+=("cf-agent: https://cfengine.com/downloads  (or: cfengine install)")
command -v cf-promises >/dev/null 2>&1  || _missing+=("cf-promises: installed with cf-agent")
command -v cfengine >/dev/null 2>&1     || _missing+=("cfengine CLI: pipx install cfengine")
if (( ${#_missing[@]} > 0 )); then
    echo "MISSING TOOLS:" >&2
    for m in "${_missing[@]}"; do echo "  - $m" >&2; done
fi

# Context output (enters the rendered skill)
echo "Docs: $DOCS_DIR (branch: $BRANCH)"
echo "Reference: $DOCS_DIR/content/reference/"
command -v cf-agent >/dev/null 2>&1 && echo "cf-agent: $(cf-agent -V 2>/dev/null | head -1)"
command -v cfengine >/dev/null 2>&1 && echo "cfengine CLI: $(cfengine --version 2>/dev/null)"
