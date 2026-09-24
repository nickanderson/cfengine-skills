Both forms work as Mission Portal would run them: the status query returns one row per failing host (`hostkey` present, no `;` or trailing `--`), and the wrapped host-list query correctly joins to produce one row per host. Sanity check confirms row count equals distinct hostkey count (1 = 1).

`alert.sql` is written and ready to paste into the alert editor's Custom SQL condition field:

```sql
SELECT DISTINCT hostkey
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
```

`promiseexecutions` already reflects each host's most recent reported agent run, so this needs no extra "latest run" filtering — `DISTINCT` collapses multiple failed promises on the same host into one alert row per host, satisfying Mission Portal's one-row-per-`hostkey` requirement.