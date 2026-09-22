That matches expectations for the example data: nginx runs, node-exporter runs (nginx is present), log-shipper runs (nginx present and today, Tuesday, is a weekday), and backup-agent correctly stays off (no postgresql in this inventory).

## Can class expressions be made case-insensitive?

No — CFEngine class names are matched as exact strings, and there's no case-insensitive flag for class expressions (`.`/`|`/`!`/`(`/`)`). `Nginx`, `nginx`, and `NGINX` define three distinct classes; a bundle or `only_if` written with `has_nginx` will simply never see `has_Nginx` or `has_NGINX`.

The fix is to canonicalize *before* the class is ever defined: lower-case the inventory's service name and turn non-alphanumeric characters into `_` (`canonify(string_downcase(name))`), then build `has_<canonical-name>` from that. Since bundles and `only_if` expressions already use lowercase names, this single normalization point makes matching casing-proof everywhere downstream — no changes needed to the `only_if` expressions themselves.

## Policy structure (`policy.cf`)

- Loads `inventory.json` via `readjson()` and, per entry, computes a canonical name (`svc_canon`).
- Evaluates classes in three explicit passes so ordering in the JSON array never matters:
  1. define `has_<canon>` for every listed service,
  2. then evaluate each entry's `only_if` expression (defaulting to `"any"` when absent) into `only_if_ok_<canon>`, so cross-service references like `has_nginx|has_postgresql` are always resolvable,
  3. then combine into `run_<canon>` = `has_X . only_if_ok_X . !in_maintenance`.
- `methods:` explicitly dispatches to the six known `svc_*` stub bundles, gated by their `run_*` class — unknown/future inventory entries are silently ignored rather than erroring.

```cfengine3
###############################################################################
# policy.cf
#
# Reads a per-host service inventory (JSON) and runs the bundle for each
# known service, provided:
#   - the service is present in the inventory,
#   - its "only_if" class expression (if any) evaluates true, and
#   - the host is not in maintenance mode.
#
# CFEngine class names are matched as literal strings: "Nginx", "nginx" and
# "NGINX" define three *different* classes. There is no case-insensitive
# mode for class expression evaluation itself. The fix applied here is to
# canonicalize every inventory service name (lower-case, non-alphanumerics
# turned into "_") *before* it is used to build a "has_<service>" class, so
# "Nginx"/"nginx"/"NGINX" all collapse onto the single class "has_nginx".
# Bundles and "only_if" expressions written in lowercase then always match,
# regardless of how the inventory happened to capitalize the name.
###############################################################################

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

bundle agent main
{
  vars:
      "inv"     data  => readjson("$(this.promise_dirname)/inventory.json", "10M");
      "svc_idx" slist => getindices("inv[services]");

      "svc_name[$(svc_idx)]"
        string => "$(inv[services][$(svc_idx)][name])";

      # Canonicalize: lower-case, then turn anything non-alphanumeric
      # (e.g. "-") into "_", so "Nginx"/"nginx"/"NGINX"/"Node-Exporter"
      # all resolve to one predictable, lowercase class-name fragment.
      "svc_canon[$(svc_idx)]"
        string => canonify(string_downcase("$(svc_name[$(svc_idx)])"));

      # Default only_if to "any" (always true) when the inventory entry
      # doesn't carry one.
      "only_if[$(svc_idx)]"
        string => "$(inv[services][$(svc_idx)][only_if])",
        if     => isvariable("inv[services][$(svc_idx)][only_if]");

      "only_if[$(svc_idx)]"
        string => "any",
        if     => not(isvariable("inv[services][$(svc_idx)][only_if]"));

  classes:
      "in_maintenance"
        expression => strcmp("$(inv[maintenance])", "true");

      # Pass 1: define has_<canonical-name> for every inventory entry, for
      # every service, before any only_if expression is evaluated - an
      # only_if may reference another service's has_ class (e.g.
      # node-exporter depends on has_nginx), regardless of list order.
      "has_$(svc_canon[$(svc_idx)])"
        expression => "any";

      # Pass 2: evaluate each entry's only_if class expression (written by
      # the inventory team using lowercase has_ names and CFEngine's
      # built-in, correctly-cased day-of-week classes).
      "only_if_ok_$(svc_canon[$(svc_idx)])"
        expression => "$(only_if[$(svc_idx)])";

      # Pass 3: the final go/no-go per service.
      "run_$(svc_canon[$(svc_idx)])"
        expression => "has_$(svc_canon[$(svc_idx)]).only_if_ok_$(svc_canon[$(svc_idx)]).!in_maintenance";

  methods:
      "nginx"         usebundle => svc_nginx,         ifvarclass => "run_nginx";
      "postgresql"    usebundle => svc_postgresql,    ifvarclass => "run_postgresql";
      "node_exporter" usebundle => svc_node_exporter, ifvarclass => "run_node_exporter";
      "log_shipper"   usebundle => svc_log_shipper,   ifvarclass => "run_log_shipper";
      "backup_agent"  usebundle => svc_backup_agent,  ifvarclass => "run_backup_agent";
      "redis"         usebundle => svc_redis,         ifvarclass => "run_redis";
}

body common control
{
      bundlesequence => { "main" };
}
```

Both files are in the working directory (`policy.cf`, `inventory.json`). I verified with `cf-agent -K -f ./policy.cf` against the example data (nginx/node-exporter/log-shipper configure, backup-agent correctly withheld since postgresql isn't listed), against mixed-case variants (`NGINX`, `PostgreSQL`, `node-exporter`, `REDIS` all matched correctly), and confirmed `"maintenance": true` suppresses every service.