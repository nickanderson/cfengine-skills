Works cleanly: `svc_nginx` and `svc_node_exporter` run unconditionally-ish, `svc_log_shipper` runs because today is a weekday, and `svc_backup_agent` correctly stays off (no `postgresql` in inventory, and it's not the weekend anyway).

## Can class expressions be made case-insensitive?

No — CFEngine class names and class expressions are case-sensitive with no flag or syntax to turn that off (`role_batch` and `role_Batch` are different classes). But you don't need the *expression* to be case-insensitive — you need the *class you define* to always come out in one casing. The fix is to normalize the casing once, at the point where you turn an inventory string into a class name (`string_downcase(canonify(name))`), so `Nginx`, `nginx`, and `NGINX` all define the same `has_nginx` class. The `only_if` expressions and your bundle logic then stay lowercase and never need to special-case input casing.

Two things to be careful of:
- Only normalize the classes you *define* from inventory data — never blanket-downcase an `only_if` expression itself, since it may also reference mixed-case hard classes like `Monday`/`Tuesday` that must stay as-is.
- A `classes:` promise silently canonifies invalid characters (e.g. `Node-Exporter` → `has_node_exporter`), but testing an expanded name does not — so any place a computed name is used in an `if =>` test needs `canonify()` (I applied it at definition time, so the class names used in tests are already clean).

## Policy

Structure: `main` reads `inventory.json`, builds a `has_<service>` class per entry (casing folded away), defaults `only_if` to `any` when absent, guards against inventory entries that don't map to a known bundle (so a typo never aborts the whole run via `usebundle`), and calls the matching `svc_*` bundle only when the service is listed, its `only_if` holds, and the host isn't in maintenance.

`policy.cf`:
```cfengine3
body common control
{
      bundlesequence => { "main" };
}

# ---------------------------------------------------------------------
# main: reads inventory.json, normalizes casing of service names into
# has_<service> classes, and runs the matching svc_<service> bundle when
# the service is listed, its only_if (if any) holds, and the host is not
# in maintenance.
# ---------------------------------------------------------------------
bundle agent main
{
  vars:
      "inventory"
        data => readjson("$(this.promise_dirname)/inventory.json", 1M);

      "service_idx"
        slist => getindices("inventory[services]");

      # Map of every service bundle this policy knows how to run, keyed by
      # the lower-cased, canonified service name. Acts as both the
      # name -> bundle lookup and the "do we know this service" guard.
      "known_bundles"
        data => parsejson('{
          "nginx": "svc_nginx",
          "postgresql": "svc_postgresql",
          "node_exporter": "svc_node_exporter",
          "log_shipper": "svc_log_shipper",
          "backup_agent": "svc_backup_agent",
          "redis": "svc_redis"
        }');

      "name[$(service_idx)]"
        string => "$(inventory[services][$(service_idx)][name])";

      # Normalize casing here, once, when we compute the class/lookup key --
      # not in the only_if expressions, which also reference mixed-case
      # day-of-week hard classes that must stay untouched.
      "service_canon[$(service_idx)]"
        string => string_downcase(canonify("$(name[$(service_idx)])"));

  classes:
      "maintenance"
        expression => strcmp("$(inventory[maintenance])", "true");

      # Defines e.g. has_nginx regardless of whether the inventory said
      # Nginx, nginx or NGINX -- casing is folded away right here.
      "has_$(service_canon[$(service_idx)])"
        expression => "any";

      # True only if service_canon names a bundle we actually ship, so an
      # unrecognized inventory entry never reaches usebundle below.
      "known_$(service_idx)"
        expression => isvariable("known_bundles[$(service_canon[$(service_idx)])]");

      # only_if is optional in the inventory; tracked so the vars below can
      # default it to "any" instead of referencing a key that may not exist.
      "has_only_if_$(service_idx)"
        expression => isvariable("inventory[services][$(service_idx)][only_if]");

  vars:
      "bundle_name[$(service_idx)]"
        string => "$(known_bundles[$(service_canon[$(service_idx)])])",
        if => "known_$(service_idx)";

      "only_if[$(service_idx)]"
        string => "$(inventory[services][$(service_idx)][only_if])",
        if => "has_only_if_$(service_idx)";

      "only_if[$(service_idx)]"
        string => "any",
        unless => "has_only_if_$(service_idx)";

  methods:
      "$(service_idx)"
        usebundle => "$(bundle_name[$(service_idx)])",
        if => "has_$(service_canon[$(service_idx)]).known_$(service_idx).!maintenance.($(only_if[$(service_idx)]))";
}

# ---------------------------------------------------------------------
# Service bundle stubs
# ---------------------------------------------------------------------
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

`inventory.json` (the example from the prompt, written to the same directory):
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

Verified with `cf-promises --full-check` and `cf-agent -K -f ./policy.cf` (also tested with `Nginx`/`nginx`/`NGINX` mixed casing collapsing correctly into one `has_nginx`/`svc_nginx`, `maintenance: true` suppressing everything, and an unrecognized service name being skipped rather than aborting the run).