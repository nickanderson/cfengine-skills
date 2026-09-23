All three scenarios confirmed: normal casing, scrambled casing (`NGINX`, `PostgreSQL`, `node-exporter`, `REDIS`), and maintenance mode all behave correctly.

## Answer

No — CFEngine class names and class expressions (the `.`/`|`/`!`/`(...)` operators used in things like `only_if`) are matched as **exact, case-sensitive strings**. There's no case-insensitive mode for class expression evaluation, so you can't fix this by changing how `only_if` gets evaluated.

The fix has to happen once, upstream, at the point where an inventory entry becomes a class name: lowercase (and canonify) the service name before building `has_<service>`. Do that consistently and every `only_if` expression and bundle — which already use the lowercase convention — lines up automatically, regardless of whether the inventory says `Nginx`, `nginx`, or `NGINX`.

## Policy

`policy.cf`:
```cf
body common control
{
      bundlesequence => { "main" };
}

bundle agent main
{
  vars:
      "inventory" data => readjson("$(this.promise_dirname)/inventory.json", 1000000);

      "service_idx" slist => getindices("inventory[services]");

      "svc_name[$(service_idx)]"
          string => "$(inventory[services][$(service_idx)][name])";

      # Canonicalize once, here, so "Nginx" / "nginx" / "NGINX" all become
      # the same class name; CFEngine class expressions are case-sensitive
      # and have no case-insensitive matching mode.
      "svc_canon[$(service_idx)]"
          string => canonify(string_downcase("$(svc_name[$(service_idx)])"));

  classes:
      "is_maintenance"
          expression => strcmp("$(inventory[maintenance])", "true");

      "has_$(svc_canon[$(service_idx)])"
          expression => "any";

      "svc_has_only_if_$(service_idx)"
          expression => isvariable("inventory[services][$(service_idx)][only_if]");

      "svc_only_if_ok_$(service_idx)"
          expression => "$(inventory[services][$(service_idx)][only_if])",
          if => "svc_has_only_if_$(service_idx)";

      "svc_only_if_ok_$(service_idx)"
          expression => "any",
          if => "!(svc_has_only_if_$(service_idx))";

      "run_$(svc_canon[$(service_idx)])"
          expression => "has_$(svc_canon[$(service_idx)]).svc_only_if_ok_$(service_idx).!is_maintenance";

  methods:
      "nginx"          usebundle => svc_nginx,         ifvarclass => "run_nginx";
      "postgresql"     usebundle => svc_postgresql,    ifvarclass => "run_postgresql";
      "node_exporter"  usebundle => svc_node_exporter, ifvarclass => "run_node_exporter";
      "log_shipper"    usebundle => svc_log_shipper,   ifvarclass => "run_log_shipper";
      "backup_agent"   usebundle => svc_backup_agent,  ifvarclass => "run_backup_agent";
      "redis"          usebundle => svc_redis,         ifvarclass => "run_redis";
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

`inventory.json` (the example from the prompt):
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

Design notes:
- `svc_canon` lowercases + canonifies the name (`Node-Exporter` → `node_exporter`), so `has_<service>` and `run_<service>` are always built from a normalized name, independent of inventory casing.
- `only_if` strings are evaluated as raw class expressions via `expression => "$(...)"`; since they reference `has_*` classes we now always emit in lowercase, they work regardless of the source casing that produced those classes. Built-in day-of-week classes (`Monday`, etc.) are untouched — those are CFEngine's own correctly-cased hard classes, not inventory data.
- `run_<service>` is only defined when the service is both present and (`only_if` true or absent) and not in maintenance; the `methods` promises hardcode the 6 known services so no untracked/unknown inventory entry can trigger a bundle.
- Verified with `cf-agent -K -f ./policy.cf`: correctly reports nginx/node_exporter/log_shipper for the sample data (today is Tuesday), correctly reports nothing when `maintenance: true`, and correctly still matches when service names are scrambled in casing (`NGINX`, `PostgreSQL`, `node-exporter`, `REDIS`).