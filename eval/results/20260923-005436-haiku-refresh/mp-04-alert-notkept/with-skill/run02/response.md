Excellent! Both tests pass. The alert condition is verified and working. Here's your final alert.sql:

```sql
SELECT DISTINCT hostkey FROM promiseexecutions WHERE promiseoutcome = 'NOTKEPT'
```

**Verification results:**
- ✅ **Raw query test**: Returns 1 host with unkept promises  
- ✅ **Wrapped query test** (as Mission Portal executes it): Correctly identifies the failing host by name and hostkey

The alert will trigger for any host where at least one promise was not kept (`NOTKEPT`) in its most recent agent run. Ready to paste into the Mission Portal alert editor.