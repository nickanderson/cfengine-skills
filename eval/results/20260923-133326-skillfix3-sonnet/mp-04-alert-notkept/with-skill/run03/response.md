Both forms check out: the raw condition returns exactly one row per failing host (rowCount matches distinct hostkeys), and the wrapped host-list form Mission Portal actually uses resolves correctly to `hub.example.com`, which currently has a NOTKEPT promise.

**alert.sql:**
```sql
SELECT DISTINCT hostkey
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
```

Paste this into the alert's Custom SQL condition editor. It uses `promiseexecutions`, the current-state view holding each promise's outcome from the host's most recent reported run, filtered to `NOTKEPT` and collapsed to one row per host with `DISTINCT hostkey` (a host can have many not-kept promises in one run). Mission Portal counts the returned rows as failing hosts for status, and joins on `hostkey` to build the host list — both were verified against the hub above.