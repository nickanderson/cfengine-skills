Perfect! Both queries passed. The alert correctly identifies hosts with unkept promises. Here's your ready-to-use alert condition:

**`/tmp/cfeval-mp-04-alert-notkept-with-skill.rYSshUsX/work/alert.sql`:**

```sql
SELECT DISTINCT hostkey
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
```

**Verification:**
- ✅ Direct query: 1 host found with unkept promises
- ✅ Wrapped query (host list): Returns hostname and hostkey correctly
- ✅ Uses current-state `promiseexecutions` view (last run only)
- ✅ Returns one row per failing host via `DISTINCT hostkey`
- ✅ No trailing semicolon or comments

The alert will trigger for every host where any promise resulted in `NOTKEPT` in its most recent agent run. Copy this SQL directly into Mission Portal's alert editor (Dashboard → add alert → Custom SQL condition).