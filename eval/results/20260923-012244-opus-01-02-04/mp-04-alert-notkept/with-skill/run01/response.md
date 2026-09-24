I wrote the alert condition to `alert.sql` and tested it on your hub. It returns one row for every host with at least one promise not kept in its most recent agent run. Right now that's one host, `hub.example.com`.

```sql
SELECT hostkey, count(*) AS "Promises not kept"
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
GROUP BY hostkey
```

**How it works:**
- `promiseexecutions` holds only the outcomes from each host's last reported agent run, so a host drops out of the alert once it's fixed.
- `GROUP BY hostkey` gives one row per host. Mission Portal counts rows as failing hosts, so a host with several failed promises still counts once.
- It returns the `hostkey` column that Mission Portal needs to build the host list. It adds the hostname itself.
- There's no trailing `;` or `--` comment, because Mission Portal wraps the SQL in its own query and either would break it.

**Test results on your hub:**
- **As the alert status check runs it:** 1 row, so the alert would trigger.
- **As the host list runs it:** columns `Host name`, `hostkey`, `Promises not kept`, showing `hub.example.com` with 2.
- **Duplicate check:** 1 row for 1 distinct host.
- **Direct count from the view:** 1 host with 2 NOTKEPT promises, which matches.

The two promises not kept on the hub are `cfe_internal_management` → methods "CFEngine Recommendations", and `postgresql_conf_recommendations` → files `/var/cfengine/state/pg/data/postgresql.conf`. So the alert will trigger as soon as you save it.

**To add it:** go to Dashboard → add alert → Custom SQL condition, paste the contents of `alert.sql`, and set the name, severity, host scope and notifications. Alerts can't be created through the REST API, so this step is manual in the UI.