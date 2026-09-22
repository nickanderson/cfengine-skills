#!/usr/bin/env bash
# Tests for scripts/ensure-docs.sh.
#
# The script runs on every skill render, so the warm path has to be fast, quiet
# and side-effect-free -- that is as much the contract as cloning correctly.
# Everything here is hermetic: CFENGINE_DOCS_REPO points at a local fixture repo
# and a stub cf-agent supplies the version, so no network and no real CFEngine.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../scripts/ensure-docs.sh"
PASS=0 FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
contains(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1" "missing [$3] in: $(printf '%s' "$2" | head -c 200)";; esac; }
absent(){ case "$2" in *"$3"*) bad "$1" "unexpected [$3]";; *) ok "$1";; esac; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/ensure-docs-test.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT

# --- fixture remote: branches master and 3.27, each with a reference tree -----
REMOTE="$ROOT/remote"
git init -q "$REMOTE"
git -C "$REMOTE" config user.email t@t; git -C "$REMOTE" config user.name t
mkdir -p "$REMOTE/content/reference"
echo "master" > "$REMOTE/content/reference/marker.txt"
git -C "$REMOTE" add -A && git -C "$REMOTE" commit -qm init
git -C "$REMOTE" branch -M master
git -C "$REMOTE" checkout -qb 3.27
echo "3.27" > "$REMOTE/content/reference/marker.txt"
git -C "$REMOTE" commit -qam "3.27 branch"
git -C "$REMOTE" checkout -q master

# --- stub cf-agent so version detection is deterministic ---------------------
BIN="$ROOT/bin"; mkdir -p "$BIN"
make_cf_agent() { printf '#!/bin/sh\necho "CFEngine Core %s"\n' "$1" > "$BIN/cf-agent"; chmod +x "$BIN/cf-agent"; }
make_cf_agent 3.27.1

run() {  # run <docsdir> -> sets OUT / ERR / RC
  local d=$1; shift
  OUT=$(CFENGINE_DOCS_DIR="$d" CFENGINE_DOCS_REPO="$REMOTE" PATH="$BIN:$PATH" \
        bash "$SCRIPT" 2>"$ROOT/err"); RC=$?
  ERR=$(cat "$ROOT/err")
}

echo "1. fresh clone"
D="$ROOT/docs1"; run "$D"
check   "exits 0" "$RC" "0"
[ -d "$D/.git" ] && ok "clone created" || bad "clone created"
check   "checked out version branch" "$(git -C "$D" rev-parse --abbrev-ref HEAD)" "3.27"
check   "branch content is 3.27" "$(cat "$D/content/reference/marker.txt" 2>/dev/null)" "3.27"
contains "stdout announces docs dir" "$OUT" "Docs: $D (branch: 3.27)"
contains "stdout announces reference path" "$OUT" "Reference: $D/content/reference/"
[ -d "$D/content/reference" ] && ok "reference path exists" || bad "reference path exists"

echo "2. stdout carries only skill context (it is injected into the model's prompt)"
absent "no clone chatter on stdout" "$OUT" "Cloning"
absent "no update chatter on stdout" "$OUT" "updating"
contains "clone chatter goes to stderr" "$ERR" "Cloning"

echo "3. warm path is a no-op"
before=$(git -C "$D" rev-parse HEAD)
run "$D"
check   "exits 0" "$RC" "0"
absent  "does not re-clone" "$ERR" "Cloning"
check   "HEAD unchanged" "$(git -C "$D" rev-parse HEAD)" "$before"

echo "4. a fresh clone must not immediately pull"
D2="$ROOT/docs2"; run "$D2"
absent "no update on a just-made clone" "$ERR" "updating"

echo "5. stale checkout updates and picks up upstream commits"
git -C "$REMOTE" checkout -q 3.27
echo "newer" >> "$REMOTE/content/reference/marker.txt"
git -C "$REMOTE" commit -qam "upstream moves on"
git -C "$REMOTE" checkout -q master
touch -d "30 days ago" "$D/.git/FETCH_HEAD" 2>/dev/null || true
run "$D"
contains "reports it is updating" "$ERR" "updating"
contains "actually fetched the new commit" "$(cat "$D/content/reference/marker.txt")" "newer"

echo "6. fresh checkout does not pull"
git -C "$REMOTE" checkout -q 3.27
echo "notyet" >> "$REMOTE/content/reference/marker.txt"
git -C "$REMOTE" commit -qam "another upstream commit"
git -C "$REMOTE" checkout -q master
run "$D"
absent "no update when recently fetched" "$ERR" "updating"
absent "working copy not advanced" "$(cat "$D/content/reference/marker.txt")" "notyet"

echo "7. version change switches branch"
make_cf_agent 3.21.0
git -C "$REMOTE" checkout -qb 3.21 master
echo "3.21" > "$REMOTE/content/reference/marker.txt"
git -C "$REMOTE" commit -qam "3.21 branch"
git -C "$REMOTE" checkout -q master
run "$D"
check "switched to new version branch" "$(git -C "$D" rev-parse --abbrev-ref HEAD)" "3.21"
contains "stdout reports the new branch" "$OUT" "(branch: 3.21)"
make_cf_agent 3.27.1

echo "8. no cf-agent falls back to master, and says so on stderr"
EMPTY="$ROOT/emptybin"; mkdir -p "$EMPTY"
D3="$ROOT/docs3"
OUT=$(CFENGINE_DOCS_DIR="$D3" CFENGINE_DOCS_REPO="$REMOTE" PATH="$EMPTY:/usr/bin:/bin" \
      bash "$SCRIPT" 2>"$ROOT/err"); RC=$?
ERR=$(cat "$ROOT/err")
check    "exits 0 without cf-agent" "$RC" "0"
check    "used master" "$(git -C "$D3" rev-parse --abbrev-ref HEAD 2>/dev/null)" "master"
contains "warns on stderr" "$ERR" "cf-agent not found"
contains "lists missing tools on stderr" "$ERR" "MISSING TOOLS"
absent   "no warning leaks to stdout" "$OUT" "WARNING"

echo
printf 'passed %d, failed %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
