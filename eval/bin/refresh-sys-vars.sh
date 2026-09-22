#!/usr/bin/env bash
# Dump the sys.* variables cf-agent actually defines, one name per line. Used to
# detect hallucinated sys vars in generated policy.
#
# Runs inside the eval container when one is available, so the list matches the
# environment the policy is validated in and does not carry this machine's
# identity (on the host, sys.bindir and sys.uqhost are real).
set -euo pipefail

OUT=${1:?usage: refresh-sys-vars.sh <outfile> [image]}
IMAGE=${2:-${CFEVAL_IMAGE:-}}
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

D=$(mktemp -d "${TMPDIR:-/tmp}/cfeval-sysvars.XXXXXX")
trap 'rm -rf "$D"' EXIT
cp "$HERE/../lib/noop.cf" "$D/noop.cf"
chmod 600 "$D/noop.cf"

if [ -n "$IMAGE" ] && command -v podman >/dev/null 2>&1 && podman image exists "$IMAGE" 2>/dev/null; then
  # Networking left on here (unlike validation runs): with --network=none the
  # agent reports no interfaces, and sys.interfaces / sys.hardware_mac etc.
  # would then look hallucinated in generated policy.
  raw=$(podman run --rm --hostname cfeval -v "$D:/policy:Z" -w /policy \
          "$IMAGE" cf-agent -Kn -f ./noop.cf --show-evaluated-vars=sys 2>/dev/null || true)
  src="container $IMAGE"
else
  [ -n "$IMAGE" ] && echo "refresh-sys-vars: $IMAGE unavailable, using host cf-agent" >&2
  raw=$( cd "$D" && cf-agent -Kn -f ./noop.cf --show-evaluated-vars=sys 2>/dev/null || true )
  src="host"
fi

printf '%s\n' "$raw" \
  | awk '$1 ~ /^default:sys\./ { print $1 }' \
  | sed -e 's/^default:sys\.//' -e 's/\[.*$//' \
  | sort -u > "$D/detected.txt"

# Union in the curated supplement of real-but-environment-dependent vars.
grep -vE '^\s*(#|$)' "$HERE/../lib/extra-sys-vars.txt" | sed 's/[[:space:]]*$//' \
  | cat - "$D/detected.txt" | sort -u > "$D/vars.txt"

n=$(wc -l < "$D/vars.txt")
if [ "$n" -lt 50 ]; then
  echo "refresh-sys-vars: only $n sys vars found via $src, refusing to write $OUT" >&2
  exit 1
fi
mkdir -p "$(dirname "$OUT")"
cp "$D/vars.txt" "$OUT"
echo "$n sys vars ($src) -> $OUT"
