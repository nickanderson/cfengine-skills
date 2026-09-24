Perfect! I've investigated all five issues through the CFEngine Enterprise Mission Portal API. Here are my findings:

## Summary of Diagnoses

**1. host001 (192.168.56.3) — Stale Data**
- **Cause**: `agent_not_running`
- **Hostkey**: `SHA=73391bc3fefecd394b294f8e29b6f1efe1007de652d7479da654542b08d8153f`
- **Last agent run**: `2026-09-24T13:10:54+00:00`
- **Last collected**: `2026-09-24T13:10:54+00:00`

The data is indeed stale: the host was first seen 24.8 hours ago but has only reported once since then. A CFEngine agent typically runs every 5 minutes, so we should see frequent reports. The 25-hour gap between first report and latest report indicates the agent is not running on its normal schedule.

**2. host002 (192.168.56.4) — Deleted but Complaining?**
- **Cause**: `no_problem`
- **Still reporting**: false

host002 has been properly deleted from Mission Portal and is no longer reporting. It doesn't appear in the host list at all, so the Health page issue must be residual—the portal has moved on.

**3. host003 (192.168.56.5) — Missing Host**
- **Cause**: `duplicate_hostname`
- **Current hostname**: `hub.example.com`
- **Hostkey**: `SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5`
- **Conflicts with**: `SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940` (the real hub)

host003 didn't disappear—it changed its hostname to `hub.example.com`, colliding with the actual hub. This could happen if the machine was renamed or its hostname configuration changed.

**4. Alice Can't See host001**
- **Cause**: `rbac_hidden`
- **Role**: `web_team`
- **Class**: `linux`

Alice's role (web_team) requires hosts to have the `linux` class. Host001 either lacks this class or has conflicting classes (windows, debian_12_14). Without the required `linux` class, the role's RBAC rules exclude it from her view.

**5. Hub Listed on Health Page**
- **Cause**: `duplicate_hostname`
- **Caused by**: `SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5`

The actual hub (192.168.56.2) and host003 (192.168.56.5) both report as `hub.example.com`. This hostname collision creates confusion on the health page. Host003 is the culprit—it incorrectly adopted the hub's hostname.

The `diagnosis.json` file has been saved to the working directory with all findings.