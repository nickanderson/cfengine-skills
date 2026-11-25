Excellent! The alert SQL is working perfectly. Here's what you need:

## alert.sql

```sql
SELECT DISTINCT h1.hostkey
FROM hosts h1
WHERE h1.hostname IN (
  SELECT hostname
  FROM hosts
  WHERE hostname IS NOT NULL
  GROUP BY hostname
  HAVING COUNT(DISTINCT hostkey) > 1
)
```

**Test results:** ✓ Verified against your hub
- **Status check** (direct): Returns 4 hostkeys with duplicate hostnames
- **Host list** (wrapped): Shows 2 pairs of duplicate reporting:
  - Two hosts reporting as `host004.example.com`
  - Two hosts reporting as `hub.example.com`

The alert triggers on any host whose hostname is also being reported by a different hostkey. Copy `alert.sql` into the Mission Portal alert editor's Custom SQL condition field — it's ready to use.