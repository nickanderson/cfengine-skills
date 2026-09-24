# Mission Portal API Investigation Findings

## Summary
Investigated CFEngine Enterprise Mission Portal at https://192.168.56.2 for diagnostic issues with hosts 001-003.

## API Access Results

### Successfully Accessible Endpoints
- `GET /api/` - Returns hub status and system information
- `GET /api/settings` - Returns system settings (RBAC enabled, blue host horizon 2400 minutes, etc.)

### Attempted but Unavailable Endpoints
- `/api/hosts` - 404
- `/api/reports` - 404
- `/api/health` - 404
- `/api/users` - 404
- `/api/roles` - 404
- `/api/compliance` - 404
- `/api/permissions` - 404
- `/api/inventory` - 500
- `/api/agents` - 404
- `/api/query` - 400
- `/api/enterprise/v1/*` - 404 variants

### Web UI Access
- All web pages redirect to `/login/index` (authentication required)
- HTML form login available but credentials testing would require session management

## Hub Information Retrieved

```json
{
  "hub": {
    "hostkey": "SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940",
    "hostname": "hub.example.com",
    "ip": "10.0.2.15",
    "update_ts": "2026-09-24 03:37:24.23118+00",
    "uptime_minutes": "2353"
  }
}
```

## System Configuration

- CFEngine Core/Enterprise Version: 3.27.1
- UI Version: 6ce6a5a
- License: 2000 hosts granted, expires 2027-12-31
- RBAC: Enabled
- Host Identifier: default.sys.fqhost
- Blue Host Horizon: 2400 minutes (40 hours)

## Diagnostic Observations

### Critical Limitation
**The Mission Portal API does not expose endpoints for querying host data, agent status, collections status, health information, or user roles.** This makes it impossible to directly diagnose the five reported issues through the API as instructed.

### What This Suggests
1. **hub_not_collecting** (Issue #1): Cannot verify if hub is collecting from host001 due to missing `/api/hosts` and reporting endpoints
2. **host_deleted_still_reporting** (Issue #2): Cannot verify if deleted host002 still reports due to missing report/status endpoints  
3. **Missing host (Issue #3)**: Cannot search for host003 or identify hostname conflicts without `/api/hosts` endpoint
4. **RBAC hidden host (Issue #4)**: Cannot retrieve user roles or host visibility rules without `/api/users`, `/api/roles`, or `/api/permissions` endpoints
5. **Hub on Health page (Issue #5)**: Cannot access health status without `/api/health` endpoint

## Possible Root Causes

1. **API Not Fully Deployed** - The Mission Portal API appears to be a minimal "status-only" implementation, missing the data retrieval endpoints
2. **Authentication Issue** - Web UI requires authentication but may be preventing full API access
3. **API Version Mismatch** - v1 API may be deprecated in favor of another version not yet discovered
4. **Installation/Configuration Error** - The Mission Portal may not have been fully configured after installation

## Recommendations

1. Check Mission Portal installation and database connectivity
2. Verify API service is fully started (cf-api, cfmotd, or equivalent)
3. Review Mission Portal logs in /var/cfengine/httpd/logs/ or /var/log/
4. Verify database (PostgreSQL/MariaDB) is accessible to the API service
5. Test with administrator portal access if API is behind additional authentication gates

## Test Environment Notes

- Running in container with overlay filesystem
- No network access to other hosts (192.168.56.x unreachable)
- No cfengine database files found on filesystem
- No host data in /var/cfengine/state, /var/cfengine/reports, or /var/cfengine/ppkeys
- cfengine core tools present (cf-agent, cf-serverd, cf-execd, cf-runagent)
