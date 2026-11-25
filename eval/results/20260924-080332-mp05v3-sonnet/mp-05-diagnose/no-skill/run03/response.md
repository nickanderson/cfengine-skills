## Findings

**1. host001 (192.168.56.3) — `no_problem`**
`Hosts.lastreporttimestamp` for `SHA=7339...8153f` is `2026-09-24T13:20:53+00:00`, about 90 seconds before the query — the hub is collecting normally. Every promise in `PromiseExecutions` for this host is `KEPT` (49/49), and `hostkeycollisions = 0`. The agent is running on schedule and the hub is collecting on schedule; there's no actual staleness — just a false alarm.

**2. host002 (192.168.56.4) — `host_deleted_still_reporting`**
host002 itself has zero trace anywhere (not in `Hosts`, `Variables`, `Contexts`, `Inventory`, `Software`) — it was cleanly deleted and is not reporting. But a *different* decommissioned host, `SHA=evaldel2` (`lab-decomm01.example.com`), still has fresh rows in `Variables`/`Contexts`/`Inventory` with no matching `Hosts` entry — i.e., it was deleted from Mission Portal but keeps reporting, last seen `2026-09-23T07:04:18+00:00`. That's what the Health page is actually complaining about; the user misattributed it to host002.

**3. host003 (192.168.56.5) — `hostname_changed`**
There's no host named `host003*` anymore, but `SHA=f20c...9c5` at IP `192.168.56.5` (host003's original address) now reports `sys.fqhost = hub.example.com`. host003 didn't disappear — its hostname changed to `hub.example.com`, colliding with the real hub (`SHA=6bb7...940`).

**4. Alice / host001 — `rbac_hidden`**
Alice's role `web_team` has `includeContext=linux`, `excludeContext=windows|debian_12_14`. host001 reports both `linux` and `debian_12_14` classes — the exclude context wins, so `web_team` never sees it even though it's a Linux host.

**5. Hub (192.168.56.2) on the Health page — `duplicate_hostname`**
Nothing is wrong with the real hub itself. It's caused by host003 (`SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5`), which now reports hostname `hub.example.com` (see #3), producing two hosts with the same name and tripping the Health check that flags the real hub.

Findings are written to `diagnosis.json` in the working directory.