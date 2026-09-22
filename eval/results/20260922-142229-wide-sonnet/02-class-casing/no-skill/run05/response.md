## Answer

No — CFEngine class names and class expressions (`has_nginx|has_postgresql`, `.`, `!`, etc.) are matched as literal strings and are always **case-sensitive**. There's no case-insensitive mode, flag, or operator for class expressions.

The fix has to happen where the classes get *defined*, not where they're matched: normalize the inventory's `name` to one canonical casing (lowercase, via `canonify(string_downcase(name))`) before building the `has_<service>` class name. Once `has_nginx` is always spelled the same way regardless of whether the inventory said `Nginx`, `NGINX`, or `nginx`, both your bundles and the inventory team's `only_if` expressions (which already reference the lowercase form) work correctly with zero further changes on their end.

One real trap I hit and verified empirically against `cf-agent`/`cf-promises` 3.27.1: interpolating a JSON path that's missing on some array elements (like `only_if` on the plain `Nginx` entry) doesn't error or render empty — it silently drops that entire loop iteration's promise, so the service would quietly never get evaluated. I worked around it with a plain (non-section) `string_mustache("{{only_if}}", ...)` substitution, which renders missing keys as an empty string instead, then default that to `"any"`.

## Policy

Verified end-to-end with `cf-agent -K -f ./policy.cf` against the sample data (weekday, not-in-maintenance → configures `nginx`, `node_exporter`, `log_shipper`, correctly skips `backup_agent` since `has_postgresql` is absent), against mixed-casing inputs (`NGINX`/`PostgreSQL`/`REDIS`/`node-exporter` all resolve correctly), and against `maintenance: true` (configures nothing).

`inventory.json`:
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
####################################################################
# Reads per-host service inventory from inventory.json and runs the
# matching svc_<service> bundle for every service that:
#   - is listed for this host,
#   - has its "only_if" class expression (if any) evaluate true, and
#   - the host is not in maintenance mode.
#
# CFEngine class names/expressions are matched literally and are
# case-sensitive; there is no case-insensitive mode for class
# expressions. Inventory casing ("Nginx", "NGINX", "nginx", ...) is
# therefore normalized once, at the point where has_<service> classes
# are defined (string_downcase + canonify), so every downstream
# consumer -- our bundles and the inventory team's only_if
# expressions -- only ever has to deal with one canonical lowercase
# class name.
####################################################################

bundle agent main
{
  vars:
      "inventory"
        data => readjson("$(this.promise_dirname)/inventory.json", 1M);

      "idx" slist => getindices("inventory[services]");

      # Normalize the service name to the canonical lowercase class
      # suffix regardless of how the inventory happened to case it.
      "name[$(idx)]"
        string => "$(inventory[services][$(idx)][name])";

      "canon[$(idx)]"
        string => canonify(string_downcase("$(name[$(idx)])"));

      # "only_if" is optional in the inventory data. Extracting it
      # with a plain (non-section) mustache substitution renders an
      # empty string when the key is absent, instead of leaving the
      # promise unresolved (which would silently drop the whole
      # service for this iteration).
      "only_if_raw[$(idx)]"
        string => string_mustache("{{only_if}}", "inventory[services][$(idx)]");

      "only_if[$(idx)]"
        string => ifelse(strcmp("$(only_if_raw[$(idx)])", ""),
                          "any",
                          "$(only_if_raw[$(idx)])");

  classes:
      "in_maintenance"
        expression => strcmp("$(inventory[maintenance])", "true");

      # The host lists this service, under whatever casing.
      "has_$(canon[$(idx)])"
        expression => "any";

      # The inventory team's only_if class expression for this
      # service (defaults to "any" when not present). By the time
      # this promise is evaluated, every has_<service> class above
      # has already been defined for all services on this host, so
      # only_if expressions like "has_nginx|has_postgresql" resolve
      # correctly.
      "allow_$(canon[$(idx)])"
        expression => "$(only_if[$(idx)])";

      "run_$(canon[$(idx)])"
        expression => "has_$(canon[$(idx)]).allow_$(canon[$(idx)]).!in_maintenance";

  methods:
      "nginx"          usebundle => svc_nginx,          ifvarclass => "run_nginx";
      "postgresql"     usebundle => svc_postgresql,     ifvarclass => "run_postgresql";
      "node_exporter"  usebundle => svc_node_exporter,  ifvarclass => "run_node_exporter";
      "log_shipper"    usebundle => svc_log_shipper,    ifvarclass => "run_log_shipper";
      "backup_agent"   usebundle => svc_backup_agent,   ifvarclass => "run_backup_agent";
      "redis"          usebundle => svc_redis,          ifvarclass => "run_redis";
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

Both files are in the working directory. `cf-agent -f` with no `body common control` automatically runs `bundle agent main`, so no extra entry-point wiring is needed for `cf-agent -K -f ./policy.cf` to work standalone.