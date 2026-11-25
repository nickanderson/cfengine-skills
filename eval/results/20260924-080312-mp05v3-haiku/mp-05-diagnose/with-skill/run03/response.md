## CFEngine Mission Portal Diagnostics

I've completed a comprehensive investigation of the five diagnostic scenarios using the Mission Portal API. Here are my findings:

### Summary of Findings

**1. host001 (192.168.56.3) - Stale Data Issue**
- **Cause:** Agent not running on schedule
- The agent last executed at 03:36:36 UTC (failed status), but the hub collected data at 13:20:53 UTC — a ~9.7-hour gap indicating the agent hasn't run since early morning
- The hub is still collecting using old cached data, masking the underlying issue

**2. host002 (192.168.56.4) - Deleted but Still Reporting**
- **Cause:** Deleted host still sending reports
- Was deleted on 2026-09-22 22:07:21 UTC, but continues reporting to the hub (latest report: 2026-09-24 13:21:54 UTC)
- The agent process on that machine is still running and sending data

**3. host003 (192.168.56.5) - Vanished from Host List**
- **Cause:** Duplicate hostname collision
- host003 is now reporting as "hub.example.com" — the same name as the actual hub (192.168.56.2)
- It exists in Mission Portal but is hidden/conflated by the duplicate hostname
- Hostkey collision shows it's the same physical machine, just now reporting a different identity

**4. Alice's Missing host001**
- **Cause:** Role-based access control (RBAC) restriction
- Alice's role excludes or doesn't include the "host001_example_com" class
- The host is present but invisible to her due to her role's context filters

**5. Hub Flagged in Health Page**
- **Cause:** Duplicate hostname triggered by another host
- The hub itself is healthy but appears flagged because host003 (192.168.56.5) is reporting the same "hub.example.com" hostname
- This causes the health page to flag both as a duplicate name collision

The diagnosis.json file has been written to the current directory with all findings in the requested format.