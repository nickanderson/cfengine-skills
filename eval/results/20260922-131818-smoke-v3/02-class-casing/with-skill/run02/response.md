## Is case-insensitive class matching possible?

No — CFEngine class names and class expressions are always matched literally and case-sensitively. There's no flag or evaluation mode that folds case when a class expression like `has_nginx|has_postgresql` is evaluated. `has_Nginx`, `has_nginx`, and `has_NGINX` are three distinct, unrelated classes.

The fix isn't to change how expressions are *evaluated* — it's to control what classes get *defined* in the first place. Since your bundles and `only_if` expressions already consistently use lowercase names, the policy should canonicalize the inventory's service name (lowercase + `canonify()`) before turning it into a `has_<service>` class. Do that once, and every `has_<service>` class collapses onto the same lowercase name regardless of how the inventory happened to case it — so the existing lowercase `only_if` expressions and bundle names just work.

## Policy

`svc_nginx`/`svc_postgresql`/etc. only need the `has_<service>` classes to be consistently lowercase; the `only_if` expressions are evaluated dynamically per-entry via `ifvarclass`, defaulting to `any` when absent.

```cfengine3
body common control
{
      bundlesequence => { "main" };
}

bundle agent main
{
  vars:
      "inv" data => readjson("$(this.promise_dirname)/inventory.json", "1M");

      "service_idx" slist => getindices("inv[services]");

      "raw_name[$(service_idx)]"
        string => "$(inv[services][$(service_idx)][name])";

      "canon_name[$(service_idx)]"
        string => canonify(string_downcase("$(raw_name[$(service_idx)])"));

      "only_if_expr[$(service_idx)]"
        string => "$(inv[services][$(service_idx)][only_if])",
        if => isvariable("inv[services][$(service_idx)][only_if]");

      "only_if_expr[$(service_idx)]"
        string => "any",
        unless => isvariable("inv[services][$(service_idx)][only_if]");

  classes:
      # Normalize inventory casing (Nginx, NGINX, nginx, ...) down to one
      # canonical lowercase class so bundles/only_if expressions match
      # regardless of how the inventory team cased the service name.
      "maintenance"
        expression => "true",
        if => strcmp("$(inv[maintenance])", "true");

      "has_$(canon_name[$(service_idx)])"
        expression => "true";

      "should_run_$(canon_name[$(service_idx)])"
        expression => "true",
        ifvarclass => "!maintenance.($(only_if_expr[$(service_idx)]))";

  methods:
      "nginx"
        usebundle => svc_nginx,
        ifvarclass => "should_run_nginx";

      "postgresql"
        usebundle => svc_postgresql,
        ifvarclass => "should_run_postgresql";

      "node_exporter"
        usebundle => svc_node_exporter,
        ifvarclass => "should_run_node_exporter";

      "log_shipper"
        usebundle => svc_log_shipper,
        ifvarclass => "should_run_log_shipper";

      "backup_agent"
        usebundle => svc_backup_agent,
        ifvarclass => "should_run_backup_agent";

      "redis"
        usebundle => svc_redis,
        ifvarclass => "should_run_redis";
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

`inventory.json` (example export, as given):

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

### How it works
- Each inventory entry's `name` is canonicalized with `string_downcase()` + `canonify()` before becoming `has_<service>` — `Nginx`/`nginx`/`NGINX` all produce `has_nginx`.
- `only_if`, when present, is evaluated as a genuine dynamic class expression via `ifvarclass` (not `eval()`, which only supports numeric/math expressions) — so `has_nginx|has_postgresql` and nested day-of-week logic work as-is.
- Missing `only_if` defaults to the hard class `any` via `isvariable()`/`if`/`unless`, so services without one still run (subject to maintenance).
- `maintenance` gates every `should_run_*` class via `!maintenance`.
- Six explicit `methods:` promises call only the known bundles; unrecognized inventory entries (e.g., `Unknown-Thing`) still get a `has_*`/`should_run_*` class defined but no bundle is invoked for them.

Verified with `cf-promises -cf` and `cf-agent -K -f ./policy.cf` against the example data (fires `svc_nginx`, `svc_node_exporter`, `svc_log_shipper` on a Tuesday with no postgresql), plus maintenance=true (nothing fires), mixed-case names (`NGINX`, `PostgreSQL`, `nginx`), and unknown service names (ignored without error).