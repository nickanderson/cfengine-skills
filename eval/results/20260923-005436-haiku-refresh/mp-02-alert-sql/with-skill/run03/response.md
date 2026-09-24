Perfect. The alert condition is tested and working. Here's what it found:

**Test Results:**
- ✅ Raw query: 2 hosts found with duplicate hostnames
- ✅ Wrapped query (as Mission Portal runs it): Returns 2 rows, both reporting `hub.example.com` but with different hostkeys — confirming it's detecting genuine duplicates

**The SQL is ready to paste into the Mission Portal alert editor:**

```sql
WITH duplicate_hostnames AS (
  SELECT hostname
  FROM hosts
  GROUP BY hostname
  HAVING count(DISTINCT hostkey) > 1
)
SELECT h.hostkey
FROM hosts h
WHERE h.hostname IN (SELECT hostname FROM duplicate_hostnames)
```

**How it works:**
1. Finds all hostnames that are reported by more than one unique host (hostkey)
2. Returns one row per host with a non-unique hostname
3. The alert will trigger when any host reports a hostname that's already in use by another host

The file `alert.sql` is ready in your work directory.