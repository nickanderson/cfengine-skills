Everything validates and runs correctly with `cf-agent -K -f ./policy.cf`.

## Can class expressions be made case-insensitive?

No — not directly. CFEngine class names are plain strings, and the `.`/`|`/`!` class-expression operators do exact, case-sensitive string comparison against the currently-defined class set. There's no "case-insensitive" mode for class-expression evaluation itself.

The fix is to normalize *before* a class name is ever created, not to try to make matching insensitive afterward. Since the casing problem originates from the inventory's `name` field, the policy downcases and canonifies that value (`canonify(string_downcase(name))`) when building each `has_<service>` class. `Nginx`, `nginx`, and `NGINX` all collapse to the identical class `has_nginx`, so every check against it — including the `only_if` expressions, which are already written by the inventory team using the correct lowercase form — matches regardless of source casing. That also means bundle dispatch (`svc_nginx`) and `only_if` evaluation both key off the same normalized suffix, so casing drift can't split them apart again.

One real bug surfaced while building this: CFEngine's `vars`/`classes` promise types are evaluated as whole groups across a bundle (all `vars:` before all `classes:`), not in the interleaved order they're written, and each pass runs 3 times with classes staying "sticky" once set true. Guarding an `only_if`-default lookup with a separately-declared class caused a spurious pass-1 default to leak through and stick. That's fixed by using `if`/`unless` (which evaluate a context function immediately, in the same promise) instead of `ifvarclass` against a class defined in an earlier promise type.

## Policy

`policy.cf`:
```cfengine3
body common control
{
      bundlesequence  => { "main" };
}

bundle agent main
# @brief Read the inventory export and run the service bundle for each
# service the host lists, subject to its `only_if` class and maintenance mode.
{
  vars:
      "inventory"
        data => readjson("$(this.promise_dirname)/inventory.json", 1048576);

      "service_idx"
        slist => getindices("inventory[services]");

      # Case-insensitive matching happens here: the class suffix is derived
      # by downcasing + canonifying the inventory name, so "Nginx", "nginx"
      # and "NGINX" all collapse to the same "has_nginx" class.
      "service_name[$(service_idx)]"
        string => canonify(string_downcase("$(inventory[services][$(service_idx)][name])"));

      "maintenance_value"
        string => "$(inventory[maintenance])";

      # Default: no only_if entry means the service is always allowed to
      # run. Guarded with if/unless (evaluated immediately, unlike
      # ifvarclass against a separately-defined class) so we never
      # dereference an "only_if" key that doesn't exist on this entry.
      "service_only_if[$(service_idx)]"
        string => "any",
        unless => isvariable("inventory[services][$(service_idx)][only_if]");

      "service_only_if[$(service_idx)]"
        string => "$(inventory[services][$(service_idx)][only_if])",
        if => isvariable("inventory[services][$(service_idx)][only_if]");

  classes:
      "maintenance"
        expression => ifelse(strcmp("$(maintenance_value)", "true"), "any", "!any");

      "has_$(service_name[$(service_idx)])"
        expression => "any";

      "only_if_ok_$(service_name[$(service_idx)])"
        expression => "$(service_only_if[$(service_idx)])";

      "do_nginx"
        expression => "has_nginx.only_if_ok_nginx.!maintenance";

      "do_postgresql"
        expression => "has_postgresql.only_if_ok_postgresql.!maintenance";

      "do_node_exporter"
        expression => "has_node_exporter.only_if_ok_node_exporter.!maintenance";

      "do_log_shipper"
        expression => "has_log_shipper.only_if_ok_log_shipper.!maintenance";

      "do_backup_agent"
        expression => "has_backup_agent.only_if_ok_backup_agent.!maintenance";

      "do_redis"
        expression => "has_redis.only_if_ok_redis.!maintenance";

  methods:
      "svc_nginx"
        usebundle => svc_nginx,
        ifvarclass => "do_nginx";

      "svc_postgresql"
        usebundle => svc_postgresql,
        ifvarclass => "do_postgresql";

      "svc_node_exporter"
        usebundle => svc_node_exporter,
        ifvarclass => "do_node_exporter";

      "svc_log_shipper"
        usebundle => svc_log_shipper,
        ifvarclass => "do_log_shipper";

      "svc_backup_agent"
        usebundle => svc_backup_agent,
        ifvarclass => "do_backup_agent";

      "svc_redis"
        usebundle => svc_redis,
        ifvarclass => "do_redis";
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

`inventory.json` (the example from the prompt, used as the sample data file):
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

Tested with `cf-agent -K -f ./policy.cf`: nginx, node_exporter, and log_shipper get configured (today is Tuesday); backup_agent correctly stays off since `has_postgresql` is false. Also verified: `NGINX`/`nginx`/`NGINX` all map to one `svc_nginx` run, unlisted service names are silently ignored, and `maintenance: true` suppresses every bundle. Note that policy files must be mode `600` for `cf-agent` to load them (already set).