Confirmed: `decomm01.example.com` returns zero rows in the live host list, no entry in the deleted-hosts list, and the remaining host count (1) reflects the other host untouched.

## Result

Ran `remove-host.sh decomm01.example.com`:

```
Host 'decomm01.example.com' has been completely removed from Mission Portal.
```

Independent verification via SQL query and `/api/hosts/deleted` confirms the host is gone from both lists, and other hosts are unaffected.

```bash
#!/usr/bin/env bash
# Completely removes a host from CFEngine Mission Portal, by exact hostname match.
#
# Needs: MP_URL, MP_USER, MP_PASSWORD in the environment.
# Optional: MP_CACERT - path to the hub's certificate, to verify TLS.
#           Without it, certificate verification is skipped (-k).
#
# Usage: ./remove-host.sh <hostname>
set -euo pipefail

if [ $# -ne 1 ]; then
  echo "Usage: $0 <hostname>" >&2
  exit 1
fi

target=$1

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

command -v jq >/dev/null 2>&1 || { echo "Error: this script requires jq" >&2; exit 1; }

tls=(-k)
if [ -n "${MP_CACERT:-}" ]; then
  tls=(--cacert "$MP_CACERT")
fi

base=${MP_URL%/}

# mp <METHOD> <path> [json-body] -> response body on stdout; non-2xx makes curl fail.
mp() {
  local method=$1 path=$2
  local -a extra=()
  if [ $# -ge 3 ]; then
    extra=(-H 'Content-Type: application/json' --data-binary "$3")
  fi
  printf 'user = "%s:%s"\n' "$MP_USER" "$MP_PASSWORD" |
    curl -sS --fail-with-body "${tls[@]}" -K - -X "$method" "${extra[@]}" "${base}${path}"
}

# Build a safe single-quoted SQL string literal for an exact-match WHERE clause.
sql_escaped=${target//\'/\'\'}
query="SELECT hostkey FROM hosts WHERE hostname = '${sql_escaped}'"
query_body=$(jq -n --arg q "$query" '{query: $q}')

result=$(mp POST /api/query "$query_body")
hostkeys=$(printf '%s' "$result" | jq -r '.data[0].rows[]? | .[0]')

if [ -z "$hostkeys" ]; then
  echo "Error: no host named '${target}' found in Mission Portal" >&2
  exit 1
fi

# Phase 1: mark every exactly-matching host as deleted.
while IFS= read -r key; do
  [ -n "$key" ] || continue
  mp DELETE "/api/host/${key}" >/dev/null
done <<<"$hostkeys"

# Phase 2: wait for each to show up as deleted, then remove its record for good.
while IFS= read -r key; do
  [ -n "$key" ] || continue

  seen=0
  for _ in $(seq 1 120); do
    deleted_list=$(mp GET "/api/hosts/deleted?limit=10000")
    if printf '%s' "$deleted_list" | jq -e --arg k "$key" '.data[] | select(.hostkey == $k)' >/dev/null 2>&1; then
      seen=1
      break
    fi
    sleep 5
  done

  if [ "$seen" -ne 1 ]; then
    echo "Error: host ${key} (${target}) never appeared among deleted hosts" >&2
    exit 1
  fi

  mp DELETE "/api/hosts/delete-permanently/${key}" >/dev/null
done <<<"$hostkeys"

# Phase 3: verify complete removal - neither in the host list nor among deleted hosts.
while IFS= read -r key; do
  [ -n "$key" ] || continue

  if mp GET "/api/host/${key}" >/dev/null 2>&1; then
    echo "Error: host ${key} (${target}) is still present after deletion" >&2
    exit 1
  fi

  deleted_list=$(mp GET "/api/hosts/deleted?limit=10000")
  if printf '%s' "$deleted_list" | jq -e --arg k "$key" '.data[] | select(.hostkey == $k)' >/dev/null 2>&1; then
    echo "Error: host ${key} (${target}) is still listed among deleted hosts" >&2
    exit 1
  fi
done <<<"$hostkeys"

echo "Host '${target}' has been completely removed from Mission Portal."
```

Notes on design:
- Uses `/api/query` with a properly single-quoted, escaped SQL literal for an **exact** hostname match (not substring/regex), so a not-found host prints an error to stderr and exits 1 without touching anything.
- Requires `jq` and standard credential env vars (`MP_URL`/`MP_USER`/`MP_PASSWORD`), with `MP_CACERT` optional for certificate pinning; falls back to `-k` and skips verification otherwise.
- Follows the two-phase delete required by the API: `DELETE /api/host/:hostkey` (soft delete) → poll `/api/hosts/deleted` until it appears → `DELETE /api/hosts/delete-permanently/:hostkey`.
- Only exits 0 after re-checking that the host is absent from both the live host list and the deleted-hosts list.