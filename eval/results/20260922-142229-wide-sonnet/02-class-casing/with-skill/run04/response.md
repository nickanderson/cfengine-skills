## Answer

CFEngine class names and class expressions are **strictly case-sensitive with no toggle to change that** — `has_nginx` and `has_Nginx` are permanently different classes, regardless of casing in inventory data.

But that's fine, because you don't need the *expression* to be case-insensitive — you need the *class name you define* to be normalized. The fix is: when you turn an inventory value into a class, run it through `canonify(string_downcase(...))` first, so `Nginx`, `nginx`, and `NGINX` all produce the same class name (`has_nginx`). Bundles and `only_if` expressions then just consistently use that lowercase name, and it doesn't matter how the inventory casing varies. This is a normalize-at-definition-time pattern, not a case-insensitive-matching feature — there isn't one.

One related pitfall this surfaced during testing: if you reference a JSON key that might be *absent* (like a missing `only_if`) directly via `$(entry[only_if])` inside a function argument (e.g. inside `ifelse()`), the whole promise silently fails to resolve for that entry — CFEngine expands all string arguments eagerly before calling the function, even unused branches. The policy below works around that by checking for the key's presence via `getindices()` instead of touching the possibly-missing key directly.

## Policy

`inventory.json` (the example data, used as-is):

```json
{
  "maintenance": false,
  "services": [
    { "name": "Nginx" },
    { "name": "Node-Exporter", "only_if": "has_nginx|has_postgresql" },
    { "name": "Log-Shipper",   "only_if": "(has_nginx|has_postgresql).(Monday|Tuesday|Wednesday|Thursday|Friday)" },
    { "name": "Backup-Agent",  "only_if": "has_postgresql.(Saturday|Sunday)" }
  ]
}
```

`policy.cf`:

```cfengine3
body common control
{
      bundlesequence => { "main" };
}

#
# Reads the per-host service inventory and, for every service the
# inventory team lists, defines a case-insensitive "has_<service>" class
# and runs the matching svc_* bundle -- but only if:
#   - the host is not in maintenance
#   - the entry's own "only_if" class expression (if any) is true
#
bundle agent main
{
  vars:
      "inventory_path"
        string => "$(this.promise_dirname)/inventory.json";

      "raw"
        data => readjson("$(inventory_path)", 1M);

      "idx"
        slist => getindices("raw[services]");

      # Case-insensitive lookup key for each entry, e.g. "Nginx" / "NGINX"
      # / "nginx" all become "nginx".
      "svc_canon[$(idx)]"
        string => canonify(string_downcase("$(raw[services][$(idx)][name])"));

      # Keys present on this entry (e.g. "name,only_if" or just "name"),
      # used below to detect an absent "only_if" without ever referencing
      # a JSON key that might not exist -- referencing a missing key
      # directly leaves the whole promise unresolved.
      "svc_keys[$(idx)]"
        slist => getindices("raw[services][$(idx)]");

      "svc_keystr[$(idx)]"
        string => join(",", "svc_keys[$(idx)]");

  classes:
      # One "has_<service>" class per inventory entry, name normalized to
      # lowercase/canonical form so differing casing from the inventory
      # (Nginx, nginx, NGINX, ...) always matches the same class.
      "has_$(with)"
        with => "$(svc_canon[$(idx)])";

      "host_in_maintenance"
        expression => strcmp("$(raw[maintenance])", "true");

      "svc_has_only_if_$(idx)"
        expression => regcmp(".*(^|,)only_if(,|$).*", "$(svc_keystr[$(idx)])");

  vars:
      # The entry's own only_if expression, defaulting to the always-true
      # "any" hard class when the entry doesn't carry one.
      "svc_only_if[$(idx)]"
        string => "$(raw[services][$(idx)][only_if])",
        if => "svc_has_only_if_$(idx)";

      "svc_only_if[$(idx)]"
        string => "any",
        unless => "svc_has_only_if_$(idx)";

      # Name-keyed copy so the static dispatch below can look up an
      # entry's only_if expression by canonical service name.
      "only_if_by_name[$(svc_canon[$(idx)])]"
        string => "$(svc_only_if[$(idx)])";

      "nginx_only_if"
        string => ifelse(isvariable("only_if_by_name[nginx]"), "$(only_if_by_name[nginx])", "any");
      "postgresql_only_if"
        string => ifelse(isvariable("only_if_by_name[postgresql]"), "$(only_if_by_name[postgresql])", "any");
      "node_exporter_only_if"
        string => ifelse(isvariable("only_if_by_name[node_exporter]"), "$(only_if_by_name[node_exporter])", "any");
      "log_shipper_only_if"
        string => ifelse(isvariable("only_if_by_name[log_shipper]"), "$(only_if_by_name[log_shipper])", "any");
      "backup_agent_only_if"
        string => ifelse(isvariable("only_if_by_name[backup_agent]"), "$(only_if_by_name[backup_agent])", "any");
      "redis_only_if"
        string => ifelse(isvariable("only_if_by_name[redis]"), "$(only_if_by_name[redis])", "any");

  methods:
      "svc_nginx"
        usebundle => svc_nginx,
        if => "has_nginx.!host_in_maintenance.($(nginx_only_if))";

      "svc_postgresql"
        usebundle => svc_postgresql,
        if => "has_postgresql.!host_in_maintenance.($(postgresql_only_if))";

      "svc_node_exporter"
        usebundle => svc_node_exporter,
        if => "has_node_exporter.!host_in_maintenance.($(node_exporter_only_if))";

      "svc_log_shipper"
        usebundle => svc_log_shipper,
        if => "has_log_shipper.!host_in_maintenance.($(log_shipper_only_if))";

      "svc_backup_agent"
        usebundle => svc_backup_agent,
        if => "has_backup_agent.!host_in_maintenance.($(backup_agent_only_if))";

      "svc_redis"
        usebundle => svc_redis,
        if => "has_redis.!host_in_maintenance.($(redis_only_if))";
}

bundle agent svc_nginx
{
  reports:
      "CONFIGURED: svc_nginx";
}

bundle agent svc_postgresql
{
  reports:
      "CONFIGURED: svc_postgresql";
}

bundle agent svc_node_exporter
{
  reports:
      "CONFIGURED: svc_node_exporter";
}

bundle agent svc_log_shipper
{
  reports:
      "CONFIGURED: svc_log_shipper";
}

bundle agent svc_backup_agent
{
  reports:
      "CONFIGURED: svc_backup_agent";
}

bundle agent svc_redis
{
  reports:
      "CONFIGURED: svc_redis";
}
```

Validated with the real binaries: `cf-promises -cf ./policy.cf` passes, and `cf-agent -K -f ./policy.cf` against the example data (run today, a Tuesday) reports `CONFIGURED: svc_nginx`, `svc_node_exporter`, and `svc_log_shipper` (backup_agent correctly skipped — no `postgresql` in this inventory). I also confirmed: mixed-case duplicates (`NGINX` + `nginx` + an `only_if: has_nginx` entry) collapse to one `has_nginx` class and fire `svc_nginx` exactly once plus the dependent service; and `"maintenance": true` suppresses every service bundle.