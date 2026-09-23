## Can class expressions be made case-insensitive?

No — CFEngine class names and the `.`/`|`/`!` class-expression operators are always exact, case-sensitive string matches (and class names are further restricted to `[a-zA-Z0-9_]`, so a name like `Node-Exporter` isn't even a legal class name as-is). There's no case-insensitive matching mode for class expressions themselves.

What you *can* do is stop the mismatch before it becomes a class name: normalize each inventoried service name with `string_downcase()` + `canonify()` before deriving `has_<service>`, so `Nginx`, `nginx`, and `NGINX` all collapse to the same class `has_nginx`. That's what the policy below does. The `only_if` expressions you write (and the ones the inventory team writes) then just need to reference these lowercase canonical names, which is already the convention in the example data.

I verified this end-to-end with `cf-agent -K -f ./policy.cf` against the example inventory and against variants with mixed-case names (`NGINX`, `Postgresql`, `REDIS`) and `maintenance: true` — normalization and gating behave correctly in all cases.

## Policy design

- `main` reads `inventory.json`, and for each entry computes a canonical name (`canonify(string_downcase(name))`), defines `has_<canonical>` unconditionally, and defines `only_if_ok_<canonical>` (true if no `only_if` is given, otherwise the evaluated `only_if` expression — evaluated only after all `has_*` classes are defined, so cross-references like `has_nginx|has_postgresql` resolve correctly).
- A fixed `methods:` dispatch table calls each of the six known `svc_*` bundles, gated on `has_<x>.only_if_ok_<x>.!maintenance`. Unknown/unrecognized inventory entries simply never get a matching `has_*`-gated dispatch, so nothing runs for them.
- Each `svc_*` bundle is a stub that reports `CONFIGURED: <bundle name>`.

```cfengine3
bundle agent main
{
  vars:
      "inv"
        data => readjson("$(this.promise_dirname)/inventory.json", 1000000);

      "service_indices"
        slist => getindices("inv[services]");

      # Raw, as-inventoried service name for this entry
      "raw_name[$(service_indices)]"
        string => "$(inv[services][$(service_indices)][name])";

      # Canonical (lowercased, canonified) form -- this is what makes
      # "Nginx", "nginx" and "NGINX" all resolve to the same has_* class.
      "canon_name[$(service_indices)]"
        string => canonify(string_downcase("$(raw_name[$(service_indices)])"));

      "only_if_expr[$(service_indices)]"
        string => "$(inv[services][$(service_indices)][only_if])",
        if => isvariable("inv[services][$(service_indices)][only_if]");

  classes:
      # The host is in maintenance mode -- no service bundles should run.
      "maintenance"
        expression => strcmp("$(inv[maintenance])", "true");

      # has_<service>: defined for every service the inventory lists for
      # this host, regardless of how its name was cased in the export.
      "has_$(canon_name[$(service_indices)])"
        expression => "any";

      # only_if_ok_<service>: true when the entry has no only_if (nothing
      # extra required), or when its only_if class expression evaluates
      # true. Must come after the has_* classes above so any has_* classes
      # referenced by an only_if expression are already defined.
      "only_if_ok_$(canon_name[$(service_indices)])"
        expression => "any",
        if => not(isvariable("only_if_expr[$(service_indices)]"));

      "only_if_ok_$(canon_name[$(service_indices)])"
        expression => "$(only_if_expr[$(service_indices)])",
        if => isvariable("only_if_expr[$(service_indices)]");

  methods:
      "svc_nginx"
        usebundle => svc_nginx,
        if => "has_nginx.only_if_ok_nginx.!maintenance";

      "svc_postgresql"
        usebundle => svc_postgresql,
        if => "has_postgresql.only_if_ok_postgresql.!maintenance";

      "svc_node_exporter"
        usebundle => svc_node_exporter,
        if => "has_node_exporter.only_if_ok_node_exporter.!maintenance";

      "svc_log_shipper"
        usebundle => svc_log_shipper,
        if => "has_log_shipper.only_if_ok_log_shipper.!maintenance";

      "svc_backup_agent"
        usebundle => svc_backup_agent,
        if => "has_backup_agent.only_if_ok_backup_agent.!maintenance";

      "svc_redis"
        usebundle => svc_redis,
        if => "has_redis.only_if_ok_redis.!maintenance";
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

body common control
{
      bundlesequence => { "main" };
}
```

`inventory.json` (example data from the request, written alongside the policy):

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

Both files are at `policy.cf` and `inventory.json` in the working directory, mode 600 as required. Running `cf-agent -K -f ./policy.cf` against this example (today is Tuesday) reports `CONFIGURED: svc_nginx`, `svc_node_exporter`, and `svc_log_shipper`; `svc_backup_agent` correctly stays off since `postgresql` isn't in this host's inventory.