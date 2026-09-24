## Alert SQL Created and Verified ✓

I've created and tested the SQL query for detecting hosts with duplicate hostnames. Here's what it does:

**Query Logic:**
1. Looks up hostnames from the `inventory_new` table (extracted from the JSON `values` field)
2. Joins with `v_Hosts` to get the hostkey for each host
3. Filters to find hostnames reported by more than one unique hostkey
4. Excludes deleted hosts
5. Returns each host with a duplicate hostname

**Test Result:**
The query successfully found **2 hosts** reporting the same hostname (`hub.example.com`):
- `SHA=f20cfa67e6fe5edc7f0b5b0c8c335bd2e18107ea83140447313c2bdc799a89c5`
- `SHA=6bb77202d78f69e7c1fe23857c06c08af688854de965d8d5820ae1b1cae4c940`

**The SQL (ready to paste):**

```sql
SELECT h.hostkey, values->>'Host name' as hostname FROM inventory_new i JOIN v_Hosts h ON i.hostkey = h.hostkey WHERE h.deleted IS NULL AND values->>'Host name' IN (SELECT values->>'Host name' FROM inventory_new WHERE values->>'Host name' IS NOT NULL GROUP BY values->>'Host name' HAVING COUNT(DISTINCT hostkey) > 1)
```

The query is saved in `alert.sql` and has been verified against your CFEngine hub at `192.168.56.2`.