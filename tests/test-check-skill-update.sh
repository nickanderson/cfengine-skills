#!/usr/bin/env bash
# Tests for scripts/check-skill-update.sh.
#
# The contract is mostly about restraint: this runs on every skill render, so
# silence is the normal case and every line it prints spends the user's
# attention. It must also never fail a render and never modify the checkout.
# Hermetic: a local fixture repo stands in for the upstream remote, so no
# network is touched.
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SCRIPT="$HERE/../scripts/check-skill-update.sh"
PASS=0 FAIL=0

ok()   { PASS=$((PASS+1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3] got [$2]"; fi; }
contains(){ case "$2" in *"$3"*) ok "$1";; *) bad "$1" "missing [$3] in: $(printf '%s' "$2" | head -c 200)";; esac; }
absent(){ case "$2" in *"$3"*) bad "$1" "unexpected [$3]";; *) ok "$1";; esac; }

ROOT=$(mktemp -d "${TMPDIR:-/tmp}/skill-update-test.XXXXXX")
trap 'rm -rf "$ROOT"' EXIT

# --- fixture upstream holding a skill and an unrelated file ------------------
REMOTE="$ROOT/remote"
git init -q -b master "$REMOTE"
git -C "$REMOTE" config user.email t@t; git -C "$REMOTE" config user.name t
mkdir -p "$REMOTE/cfengine-policy" "$REMOTE/scripts"
echo "v1" > "$REMOTE/cfengine-policy/SKILL.md"
echo "other" > "$REMOTE/unrelated.txt"
cp "$SCRIPT" "$REMOTE/scripts/check-skill-update.sh"
git -C "$REMOTE" add -A && git -C "$REMOTE" commit -qm init

CLONE="$ROOT/clone"
git clone -q "$REMOTE" "$CLONE"
git -C "$CLONE" config user.email t@t; git -C "$CLONE" config user.name t

STATE="$ROOT/state"

run() {  # run -> sets OUT / ERR / RC; fetch forced unless FETCH_DAYS overridden
  OUT=$(CFENGINE_SKILL_UPDATE_STATE="$STATE" \
        CFENGINE_SKILL_UPDATE_INTERVAL_DAYS="${FETCH_DAYS:-0}" \
        CFENGINE_SKILL_UPDATE_NOTICE_DAYS="${NOTICE_DAYS:-7}" \
        bash "$CLONE/scripts/check-skill-update.sh" 2>"$ROOT/err"); RC=$?
  ERR=$(cat "$ROOT/err")
}

upstream_commit() {  # upstream_commit <path> <content> <msg>
  echo "$2" > "$REMOTE/$1"
  git -C "$REMOTE" add -A && git -C "$REMOTE" commit -qm "$3"
}

echo "1. up to date says nothing at all"
run
check  "exits 0" "$RC" "0"
check  "stdout empty" "$OUT" ""
check  "stderr empty" "$ERR" ""

echo "2. an upstream skill change is announced and asks before acting"
upstream_commit cfengine-policy/SKILL.md v2 "update skill"
rm -f "$STATE"; run
check    "exits 0" "$RC" "0"
contains "names the skill and the distance" "$OUT" "SKILL UPDATE AVAILABLE: cfengine-policy is 1 commit behind"
contains "asks the user first" "$OUT" "ask whether to apply it"
contains "supplies the command" "$OUT" "pull --ff-only"
contains "forbids acting unilaterally" "$OUT" "Do not update without their approval"
check    "did not actually update" "$(cat "$CLONE/cfengine-policy/SKILL.md")" "v1"

echo "3. the notice does not repeat while upstream is unchanged"
run
check "second render is silent" "$OUT" ""

echo "4. a new upstream version re-notifies"
upstream_commit cfengine-policy/SKILL.md v3 "update skill again"
run
contains "re-announced for the new sha" "$OUT" "SKILL UPDATE AVAILABLE"
contains "counts both commits" "$OUT" "2 commits behind"

echo "5. commits that do not touch the skill are not worth interrupting for"
git -C "$CLONE" pull -q --ff-only
rm -f "$STATE"; run
check "clean after pull" "$OUT" ""
upstream_commit unrelated.txt changed "unrelated change"
rm -f "$STATE"; run
check "unrelated upstream commit stays silent" "$OUT" ""

echo "6. local edits are reported, never discarded"
echo "my local edit" > "$CLONE/cfengine-policy/SKILL.md"
rm -f "$STATE"; run
contains "warns guidance may not match upstream" "$OUT" "uncommitted local changes"
check    "local edit untouched" "$(cat "$CLONE/cfengine-policy/SKILL.md")" "my local edit"

echo "7. local edits plus an upstream change refuse to blindly pull"
upstream_commit cfengine-policy/SKILL.md v4 "another skill update"
rm -f "$STATE"; run
contains "still announces the update" "$OUT" "SKILL UPDATE AVAILABLE"
contains "flags the conflict" "$OUT" "will not apply cleanly"
contains "protects the user's edits" "$OUT" "do not discard their edits"
absent   "does not hand over a blind pull command" "$OUT" "pull --ff-only"

echo "8. a broken or unreachable remote never breaks skill rendering"
git -C "$CLONE" checkout -q -- cfengine-policy/SKILL.md
git -C "$CLONE" remote set-url origin "$ROOT/does-not-exist"
rm -f "$STATE"; run
check  "still exits 0" "$RC" "0"
absent "no git noise on stdout" "$OUT" "fatal"
git -C "$CLONE" remote set-url origin "$REMOTE"

echo "9. a non-git install has nothing to offer"
PLAIN="$ROOT/plain/scripts"; mkdir -p "$PLAIN"
cp "$SCRIPT" "$PLAIN/check-skill-update.sh"
OUT=$(CFENGINE_SKILL_UPDATE_STATE="$STATE" bash "$PLAIN/check-skill-update.sh" 2>&1); RC=$?
check "exits 0 outside a checkout" "$RC" "0"
check "and says nothing" "$OUT" ""

echo "10. the kill switch works"
OUT=$(CFENGINE_SKILL_UPDATE_DISABLE=1 CFENGINE_SKILL_UPDATE_STATE="$STATE" \
      CFENGINE_SKILL_UPDATE_INTERVAL_DAYS=0 \
      bash "$CLONE/scripts/check-skill-update.sh" 2>&1); RC=$?
check "exits 0 when disabled" "$RC" "0"
check "silent when disabled" "$OUT" ""

echo "11. the fetch interval is respected"
rm -f "$STATE"
FETCH_DAYS=7 run          # writes state with a fresh last_fetch
before=$(git -C "$CLONE" rev-parse refs/remotes/origin/master 2>/dev/null)
upstream_commit cfengine-policy/SKILL.md v5 "yet another"
FETCH_DAYS=7 NOTICE_DAYS=0 run
after=$(git -C "$CLONE" rev-parse refs/remotes/origin/master 2>/dev/null)
check "no fetch while the interval holds" "$after" "$before"

echo "12. a remote that has never been fetched has nothing to compare against"
# Not the same as test 8: there the tracking ref exists and only the URL is
# broken. A repo created locally and not yet pushed has no tracking ref at all,
# which is the state this project itself was in while being written.
NOREF="$ROOT/noref"
git init -q -b master "$NOREF"
git -C "$NOREF" config user.email t@t; git -C "$NOREF" config user.name t
mkdir -p "$NOREF/cfengine-policy" "$NOREF/scripts"
echo v1 > "$NOREF/cfengine-policy/SKILL.md"
cp "$SCRIPT" "$NOREF/scripts/check-skill-update.sh"
git -C "$NOREF" add -A && git -C "$NOREF" commit -qm init
git -C "$NOREF" remote add origin "$ROOT/nowhere"
echo "local edit" > "$NOREF/cfengine-policy/SKILL.md"
rm -f "$STATE"
OUT=$(CFENGINE_SKILL_UPDATE_STATE="$STATE" CFENGINE_SKILL_UPDATE_INTERVAL_DAYS=0 \
      bash "$NOREF/scripts/check-skill-update.sh" 2>"$ROOT/err"); RC=$?
check "exits 0 with no tracking ref" "$RC" "0"
check "stays silent rather than guessing" "$OUT" ""
check "no stderr noise" "$(cat "$ROOT/err")" ""

printf '\npassed %d, failed %d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
