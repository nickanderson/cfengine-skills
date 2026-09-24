Perfect! The alert condition is validated and ready. Here's the final SQL:

```sql
SELECT DISTINCT hostkey FROM promiseexecutions WHERE promiseoutcome = 'NOTKEPT'
```

**What it does:**
- Queries the `promiseexecutions` view (current-state promise outcomes from the last agent run)
- Filters for promises with outcome `'NOTKEPT'` (not kept)
- Returns `DISTINCT hostkey` to ensure one row per failing host (since a host may have multiple unmet promises)

**Validation results:**
- ✅ Standalone query: returns 1 host (`hub.example.com`) with unmet promises
- ✅ Wrapped form (as Mission Portal runs it): correctly identifies and displays the failing host with its hostname

The SQL is in `/tmp/cfeval-mp-04-alert-notkept-with-skill.VQcZaoap/work/alert.sql`, ready to paste into the Mission Portal alert editor.