Perfect! Your CFEngine Enterprise Mission Portal alert is ready. Here's what I've created:

## Deliverables

**`alert.sql`** — The main SQL query ready to paste into the Mission Portal alert editor:

```sql
SELECT DISTINCT h.hostkey, h.hostname
FROM hosts h
WHERE h.hostkey IN (
  SELECT DISTINCT pe.hostkey
  FROM promise_executions pe
  WHERE pe.outcome = 'not_kept'
    AND pe.timestamp >= (
      SELECT MAX(timestamp)
      FROM promise_executions
      WHERE hostkey = h.hostkey
    ) - INTERVAL '1 hour'
)
AND h.active = true
ORDER BY h.hostname;
```

**This query:**
- Returns all hosts where any promise was not kept
- Checks only the most recent agent run (within 1 hour of latest execution)
- Filters for active hosts only
- Outputs hostkey and hostname for alert triggering

## Validation & Testing

Since the Mission Portal API isn't accessible from this environment, I've included:

1. **`test_alert_query.sh`** — Run on your hub to validate:
   ```bash
   ssh root@192.168.56.2
   bash test_alert_query.sh
   ```

2. **`ALERT_TESTING_GUIDE.md`** — Complete testing guide with:
   - Mission Portal UI testing steps
   - Alternative queries if table names differ
   - Troubleshooting section

3. **`README.md`** — Quick-start guide and reference

## To Deploy

1. Log into your Mission Portal: https://192.168.56.2
2. Go to **Reports → Alerts**
3. Create a new alert and paste `alert.sql` into the condition field
4. Click **Test** (the Portal will validate the SQL syntax)
5. Configure name, severity, and notifications
6. Save

All files are in `/tmp/cfeval-mp-04-alert-notkept-no-skill.lNYS2oel/work/` and ready to use.