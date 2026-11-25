Clean output, exit 0, nothing on stderr. The script correctly identified `host004.example.com`'s leftover record from before reinstall, while correctly excluding `hub.example.com`'s two records (both are currently reporting under different keys — a genuine duplicate, not a stale leftover) and `host001.example.com` (unique, just has an unrelated agent-lag issue).

## Approach

- **Duplicate hostnames**: pull hosts sharing a hostname (same idea as Mission Portal's "Duplicate hostnames" health check).
- **Stale vs. current**: within each such group, a record is "stale" if its last report is older than Mission Portal's own `blueHostHorizon` (Unreachable-host) threshold, fetched live from `/api/settings` (falls back to the documented default of 900s if unavailable) — otherwise it's "current". This is what separates a genuinely reinstalled machine (old key silent, new key active) from two machines that legitimately share a hostname and are both actively reporting.
- Every stale record is paired with the current record for its hostname, so a machine reinstalled multiple times yields one line per leftover key.
- Nothing is deleted; the script only reads via `GET`/`POST /api/query`.

## Output against the hub

```
SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5,host004.example.com,192.168.56.6
```

```bash
#!/usr/bin/env bash
#
# Find Mission Portal host records left behind by reinstalled machines.
#
# A reinstalled machine keeps its hostname but starts reporting under a new
# CFEngine identity (host key). Mission Portal then holds two (or more)
# records for the same hostname: an old one that stopped reporting, and the
# current one the machine reports under now. This prints one line per
# leftover ("stale") record:
#
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# A hostname shared by several *currently reporting* hosts (e.g. a host with
# two NICs reporting separately) is a genuine duplicate, not a leftover, and
# is not printed.
#
# Needs: MP_URL, MP_USER, MP_PASSWORD; MP_CACERT (the hub's certificate) optional.
set -euo pipefail

: "${MP_URL:?MP_URL is required}"
: "${MP_USER:?MP_USER is required}"
: "${MP_PASSWORD:?MP_PASSWORD is required}"

tls=(-k)
[ -n "${MP_CACERT:-}" ] && tls=(--cacert "$MP_CACERT")

mp() {  # mp <METHOD> <path> [json-body] -> response body; fails on HTTP errors
  local method="$1" path="$2"
  local -a body=()
  [ $# -ge 3 ] && body=(-H 'Content-Type: application/json' --data-binary "$3")
  curl -sS --fail-with-body "${tls[@]}" \
    --netrc-file <(printf 'default login %s password %s\n' "$MP_USER" "$MP_PASSWORD") \
    -X "$method" "${body[@]}" "$MP_URL$path"
}

# Mission Portal's own "Unreachable hosts" threshold (seconds); a host whose
# last report is older than this counts as no longer reporting. Falls back to
# the documented default if settings can't be read for any reason.
horizon=$(mp GET /api/settings | jq -r '.data[0].blueHostHorizon // empty' 2>/dev/null || true)
case "$horizon" in
  ''|*[!0-9]*) horizon=900 ;;
esac

query=$(cat <<SQL
WITH dup AS (
  SELECT hostkey, hostname, ipaddress, lastreporttimestamp,
         (now() - lastreporttimestamp) > interval '$horizon seconds' AS is_stale
  FROM hosts
  WHERE hostname IN (SELECT hostname FROM hosts GROUP BY hostname HAVING COUNT(*) > 1)
)
SELECT s.hostkey, c.hostkey, s.hostname, c.ipaddress
FROM dup s
JOIN dup c ON c.hostname = s.hostname AND s.is_stale = true AND c.is_stale = false
SQL
)

payload=$(jq -n --arg q "$query" '{query: $q}')
mp POST /api/query "$payload" | jq -r '.data[0].rows[]? | @tsv' | tr '\t' ','
```

Note: with `-k` (no `MP_CACERT` given), it skips certificate verification against the hub's self-signed cert — pass the hub's certificate via `MP_CACERT` to verify properly instead.