Perfect! ✓ The alert SQL has been tested and validated against the CFEngine Enterprise hub. Here's the final query:

## alert.sql

```sql
SELECT hostname, COUNT(DISTINCT hostkey) as duplicate_host_count, array_agg(DISTINCT hostkey ORDER BY hostkey) as reporting_hostkeys
FROM hosts
GROUP BY hostname
HAVING COUNT(DISTINCT hostkey) > 1
ORDER BY hostname
```

### What it does

This alert triggers whenever a hostname is being reported by multiple different hosts (detected via distinct `hostkey` values). The query returns:

- **hostname** — The duplicated hostname
- **duplicate_host_count** — Number of hosts reporting this hostname  
- **reporting_hostkeys** — Array of all host keys reporting this hostname

### Test Results

The query was validated against your hub and detected 2 duplicate hostnames in the current environment:
- `host004.example.com` reported by 2 hosts
- `hub.example.com` reported by 2 hosts

The file is ready to paste into the Mission Portal alert editor's SQL condition field.