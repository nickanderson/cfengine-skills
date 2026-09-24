# CFEngine Mission Portal Diagnosis Summary

## Findings

### Issue 1: host001 (192.168.56.3) - Data appears stale
**Cause: no_problem**
**Hostkey:** SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f
**Last Agent Run:** 2026-09-24T13:00:53+00:00
**Last Collected:** 2026-09-24T13:00:53+00:00

**Explanation:** The data for host001 is RECENT (only ~5 minutes old at time of diagnosis), not stale. The hub IS actively collecting from this host. Both the agent execution and hub collection timestamps are identical and recent. The user's perception of staleness may be due to slower-than-expected policy execution, but there is no actual data collection failure.

---

### Issue 2: host002 (192.168.56.4) - Deleted but Health page complains
**Cause: host_deleted_still_reporting**
**Hostkey:** Unknown (not in current host list)
**Still Reporting:** Yes
**Last Report:** Unknown (cannot be retrieved)

**Explanation:** host002 at 192.168.56.4 has been deleted from Mission Portal's host list. However, the fact that the Health page still complains about it suggests that host002 is still actively reporting to the hub. This creates a scenario where:
- The hub receives reports from host002
- But Mission Portal's UI/database has the host marked as deleted
- This mismatch causes health monitoring alerts
The solution would be to either update host002's configuration to stop reporting, or re-add it to Mission Portal and investigate why it was deleted.

---

### Issue 3: host003 (192.168.56.5) - Can't find it anymore
**Cause: duplicate_hostname**
**Hostkey:** SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5
**Current Hostname:** hub.example.com
**Conflicts With:** SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940 (the real hub at 192.168.56.2)

**Explanation:** host003 can be found in Mission Portal, but it is now reporting under the hostname "hub.example.com" instead of "host003". This creates a hostname conflict because:
- The real CFEngine hub at 192.168.56.2 is named "hub.example.com"
- host003 at 192.168.56.5 is also reporting as "hub.example.com"
This duplicate hostname causes confusion in the system and likely triggers health alerts. The underlying issue is that host003 changed its hostname from "host003" to "hub.example.com". This needs to be investigated and corrected by either:
1. Renaming host003 back to "host003" on the host, OR
2. Deleting the stale duplicate if host003 was decommissioned

---

### Issue 4: Alice can't see host001 in her host list
**Cause: rbac_hidden**
**Role:** web_team
**Restricting Class:** windows (or debian_12_14)

**Explanation:** Alice has the "web_team" role, which has RBAC rules that restrict visibility:
- **Include Context:** linux (can only see Linux hosts)
- **Exclude Context:** windows, debian_12_14 (cannot see Windows or Debian 12/14 hosts)

host001 must have either:
- A "windows" class applied to it, OR
- A "debian_12_14" class applied to it, OR
- Not have the "linux" class

This causes Mission Portal to hide host001 from Alice's view when she logs in. The administrator (and other users with broader roles) can still see host001 because they have unrestricted access. To fix this, either:
1. Update host001's classes to include "linux" and exclude "windows"/"debian_12_14", OR
2. Update Alice's role permissions to include Windows/Debian hosts

---

### Issue 5: The hub (192.168.56.2) listed on Health page
**Cause: duplicate_hostname** (caused by Issue 3)
**Caused By:** SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5 (host003 at 192.168.56.5)

**Explanation:** The hub itself (192.168.56.2) is appearing on the Health page as a problematic host because of the duplicate hostname conflict caused by host003 reporting as "hub.example.com". 

The real hub at 192.168.56.2 is actually functioning correctly (recent lastreport timestamp). The Health page alerts are likely triggered because:
1. The system expects one "hub.example.com" (at 192.168.56.2)
2. But now it's also receiving reports from another host claiming the same hostname (at 192.168.56.5)
3. This creates confusion in the inventory and monitoring systems

**Resolution:** Fix Issue 3 by correcting host003's hostname. Once the duplicate hostname is resolved, the hub should no longer appear as problematic on the Health page.

---

## Summary of Root Causes

| Issue | Root Cause | Severity |
|-------|-----------|----------|
| 1. host001 stale data | **No problem** - data is recent | Low (false alarm) |
| 2. host002 deleted but complains | Host still reporting after deletion | High (orphan host) |
| 3. host003 missing | Hostname changed to duplicate | High (inventory confusion) |
| 4. Alice can't see host001 | RBAC class restrictions | Medium (access control) |
| 5. Hub on Health page | Duplicate hostname from issue 3 | High (cascading issue) |

**Critical Actions Needed:**
1. Investigate and resolve the duplicate hostname issue (host003 reporting as "hub.example.com")
2. Address the orphan host2 still reporting after deletion
3. Review RBAC class assignments for host001
