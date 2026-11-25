Perfect! Both test forms work correctly. The alert SQL is ready:

**Summary:**
- **Direct form** (alert status): Returns 1 row → alert triggers ✓
- **Wrapped form** (host list in UI): Shows hostname "hub.example.com" with NOTKEPT promises ✓

The SQL is syntactically correct, uses the current-state `promiseexecutions` view (so it reflects the most recent agent run), and returns one row per failing host as required.

**File: `alert.sql`**
```sql
SELECT DISTINCT hostkey
FROM promiseexecutions
WHERE promiseoutcome = 'NOTKEPT'
```

This alert will trigger for every host where any promise was not kept in its most recent agent run. Copy the SQL directly into the Mission Portal dashboard alert editor under **Condition** → **Custom SQL**.