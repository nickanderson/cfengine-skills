#!/usr/bin/env bash
# Ensure CFEngine documentation is cloned and version-matched.
# Called from skill dynamic context blocks. stdout enters skill context.
set -euo pipefail

DOCS_DIR="${CFENGINE_DOCS_DIR:-$HOME/.local/share/cfengine/docs}"
# Overridable so the test suite can point at a local fixture repo instead
# of cloning from GitHub on every run.
DOCS_REPO="${CFENGINE_DOCS_REPO:-https://github.com/cfengine/documentation.git}"
MAX_AGE_DAYS=7

# GNU and BSD stat disagree; this script ships to other people's machines.
_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

# Detect CFEngine version
if command -v cf-agent >/dev/null 2>&1; then
    # grep -oP is GNU-only. Split into tokens and take the first that looks
    # like a version, then keep major.minor -- "CFEngine Core 3.27.1" -> "3.27".
    CF_VERSION=$(cf-agent -V 2>/dev/null | head -1 | tr ' ' '\n' \
        | grep -E '^[0-9]+\.[0-9]+' | head -1 | cut -d. -f1,2)
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
    git clone --branch "$BRANCH" --depth 1 "$DOCS_REPO" "$DOCS_DIR" >&2 2>&1
fi

# Switch branch if version changed
CURRENT_BRANCH=$(git -C "$DOCS_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
if [[ "$CURRENT_BRANCH" != "$BRANCH" && "$BRANCH" != "master" ]]; then
    echo "Switching docs from $CURRENT_BRANCH to $BRANCH..." >&2
    # --branch on clone sets a single-branch refspec, so origin/<other> does
    # not exist; fetch an explicit refspec to create the tracking ref.
    git -C "$DOCS_DIR" fetch --depth 1 origin \
        "+refs/heads/$BRANCH:refs/remotes/origin/$BRANCH" >&2 2>&1
    git -C "$DOCS_DIR" checkout -B "$BRANCH" "origin/$BRANCH" >&2 2>&1
fi

# Pull if stale
if [[ -d "$DOCS_DIR/.git" ]]; then
    # No FETCH_HEAD right after a clone: fall back to the checkout's own
    # mtime, so a just-cloned tree is not immediately considered stale.
    LAST_FETCH=$(_mtime "$DOCS_DIR/.git/FETCH_HEAD")
    [[ "$LAST_FETCH" == 0 ]] && LAST_FETCH=$(_mtime "$DOCS_DIR/.git")
    AGE_DAYS=$(( ($(date +%s) - LAST_FETCH) / 86400 ))
    if (( AGE_DAYS >= MAX_AGE_DAYS )); then
        echo "Docs checkout is ${AGE_DAYS}d old, updating..." >&2
        git -C "$DOCS_DIR" pull --ff-only >&2 2>&1 || true
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
if command -v cf-agent >/dev/null 2>&1; then
    echo "cf-agent: $(cf-agent -V 2>/dev/null | head -1)"
fi
if command -v cfengine >/dev/null 2>&1; then
    echo "cfengine CLI: $(cfengine --version 2>/dev/null)"
fi

# Optional tooling must not make a skill's dynamic block look like it failed.
exit 0
