## Summary

I've created and tested `alert.sql` with a SQL condition that detects duplicate hostnames. Here's what it does:

**The Query:**
- Finds all hostnames being reported by multiple hosts (different hostkeys)
- Returns one row per affected host with the duplicate count
- Includes the `hostkey` column required by Mission Portal
- Uses the current-state `hosts` view (no history tables that would cause false positives)

**Verified against the hub:**
✅ **Direct test:** Returns 2 rows - the two hosts (different hostkeys) both reporting `hub.example.com`  
✅ **Wrapped test:** Correctly joins with the hosts table for the host-list display

**To use in Mission Portal:**
1. Dashboard → Add Alert
2. Condition type: Custom SQL
3. Paste the contents of `alert.sql` (no semicolon, just the query as-is)
4. Set severity, scope, and notifications as desired

The query is ready to paste into the alert editor at `/tmp/cfeval-mp-02-alert-sql-no-skill.3o9YVHj7/work/alert.sql`.