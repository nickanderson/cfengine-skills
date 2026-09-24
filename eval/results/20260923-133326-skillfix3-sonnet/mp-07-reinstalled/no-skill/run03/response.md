This matches expectations from the raw data: `host004.example.com` has two host-key records at the same IP — one that stopped reporting shortly after it first appeared (stale) and one that's still reporting now (current) — while `hub.example.com`'s two records are both still actively reporting (so not flagged) and `host001.example.com` has only one record (nothing to flag).

Script output (only stdout, one line per leftover record):

```
SHA=714a84049983de056ed0e9ae967982d31a9286c015d5151081914b677d029fd4,SHA=06791f18efa2b15c5c71bcf452fa923126533938734039f0645e9f23694d24c5,host004.example.com,192.168.56.6
```

Final script:

```bash
#!/usr/bin/env bash
#
# stale-records.sh
#
# Finds leftover Mission Portal host records left behind when a machine is
# reinstalled and comes back reporting under a new CFEngine host key.
#
# For every hostname that has more than one recorded host key, the record(s)
# that stopped reporting a long time ago are treated as "stale" leftovers,
# and the record that is still reporting recently is treated as "current".
#
# Output (stdout), one line per leftover record, nothing else:
#   <stale hostkey>,<current hostkey>,<hostname>,<ip>
#
# Requires: curl, jq
# Uses env vars: MP_URL, MP_USER, MP_PASSWORD

set -euo pipefail

: "${MP_URL:?MP_URL must be set}"
: "${MP_USER:?MP_USER must be set}"
: "${MP_PASSWORD:?MP_PASSWORD must be set}"

# A host record is considered "currently reporting" if its last report was
# received within this many seconds of the hub's own clock. Anything older
# than this, for a hostname that also has a currently-reporting record under
# a different host key, is considered a stale leftover from a reinstall.
FRESH_WINDOW_SECS="${FRESH_WINDOW_SECS:-3600}"

PAGE_SIZE=1000
page=1
tmp_all=$(mktemp)
trap 'rm -f "$tmp_all"' EXIT
echo '[]' > "$tmp_all"

now_ts=""

while true; do
  resp=$(curl -sk -u "${MP_USER}:${MP_PASSWORD}" \
    "${MP_URL%/}/api/host?page=${page}&limit=${PAGE_SIZE}")

  if [ -z "$now_ts" ]; then
    now_ts=$(jq -r '.meta.timestamp' <<<"$resp")
  fi

  page_data=$(jq -c '.data // []' <<<"$resp")
  jq -c -s '.[0] + .[1]' "$tmp_all" <(echo "$page_data") > "${tmp_all}.new"
  mv "${tmp_all}.new" "$tmp_all"

  count=$(jq -r '.meta.count // 0' <<<"$resp")
  total=$(jq -r '.meta.total // 0' <<<"$resp")

  if [ "$count" -lt "$PAGE_SIZE" ] || [ "$((page * PAGE_SIZE))" -ge "$total" ]; then
    break
  fi
  page=$((page + 1))
done

jq -r \
  --argjson now "$now_ts" \
  --argjson fresh "$FRESH_WINDOW_SECS" '
  map(. + {lastreport: (.lastreport | tonumber)})
  | group_by(.hostname)
  | map(
      (map(select(($now - .lastreport) <= $fresh))) as $active
      | (map(select(($now - .lastreport) > $fresh))) as $stale
      | if ($active | length) == 1 and ($stale | length) >= 1 then
          $stale[] | [ .id, $active[0].id, $active[0].hostname, $active[0].ip ] | join(",")
        else
          empty
        end
    )
  | .[]
' "$tmp_all"
```

Notes on the approach:
- Data comes from the Mission Portal REST API's `/api/host` resource (id = host key, plus hostname, ip, firstseen, lastreport).
- Records are grouped by hostname; within a group, a record is "fresh" if its `lastreport` is within `FRESH_WINDOW_SECS` (default 1 hour) of the hub's own clock (`meta.timestamp`), otherwise "stale".
- Only groups with exactly one fresh record and at least one stale record are reported — that's the reinstall signature (old identity went quiet, new identity took over). A hostname with several *simultaneously* fresh records (e.g. two unrelated hosts sharing a name) is left alone since nothing there is a stale leftover. Nothing is deleted.