Everything checks out. Here's the answer and the final policy.

## Can class expressions be made case-insensitive?

No — CFEngine classes are strictly case-sensitive and there's no global flag to change that (hard classes like `Monday`/`Tuesday` are intentionally mixed-case, so a blanket switch would break those too). You can't fix this by rewriting the `only_if` expressions themselves.

The fix has to happen **where the class is defined**, not where it's tested: normalize the inventory-supplied service name (`string_downcase()` + `canonify()`) before turning it into a `has_<service>` class. `"Nginx"`, `"nginx"`, and `"NGINX"` all normalize to `nginx`, so they all define the single class `has_nginx`. Since the bundles and `only_if` expressions were already written in lowercase, they now match regardless of how the inventory happened to case the value that day. Hard classes referenced inside `only_if` (`Monday`, etc.) are left untouched — only the inventory-derived names get normalized.

One non-obvious pitfall hit while building this: computing a per-entry `only_if` default with `ifelse(isvariable(...), "$(inventory[services][$(idx)][only_if])", "any")` silently drops the whole variable (and everything downstream of it) for entries that lack `only_if` — referencing a container path that doesn't exist, even in the untaken branch, makes the entire promise unresolvable. The fix is two separate `if`/`unless`-gated `vars` promises instead of one `ifelse()`.

**policy.cf**
```cfengine3
#######################################################
#
# Run service bundles based on per-host inventory data.
#
# The inventory reports service names in whatever casing it likes
# ("Nginx", "NGINX", "nginx", ...). CFEngine classes are strictly
# case-sensitive with no global switch to change that, so an
# expression like "has_nginx" will never match a class literally
# named "has_Nginx" or "has_NGINX".
#
# The fix is to normalize *at the point the class is defined*:
# every service name is lower-cased and canonified before it is
# turned into a has_<service> class, so "Nginx"/"nginx"/"NGINX" all
# collapse onto the single class has_nginx. Downstream consumers
# (only_if expressions, bundle logic) only ever need to know about
# the lowercase, canonified form. Hard classes referenced inside
# only_if (e.g. Monday, Tuesday) keep their normal mixed case and
# are left untouched.
#
#######################################################

body common control
{
      bundlesequence => { "main" };
}

#######################################################

bundle agent main
{
  vars:
      "inventory"
        data => readjson("$(this.promise_dirname)/inventory.json", 1000000);

      "svc_idx"
        slist => getindices("inventory[services]");

      # Normalized (lowercase, canonified) service identifier, e.g.
      # "Nginx" / "NGINX" / "nginx" all become "nginx".
      "svc_canon[$(svc_idx)]"
        string => canonify(string_downcase("$(inventory[services][$(svc_idx)][name])"));

      # only_if defaults to "any" (always true) when the inventory
      # entry doesn't carry one. Split into two promises (rather than
      # one ifelse()) because referencing a container path that
      # doesn't exist -- even in the untaken branch -- makes the
      # whole promise unresolvable and silently drops it.
      "svc_onlyif[$(svc_idx)]"
        string => "$(inventory[services][$(svc_idx)][only_if])",
        if => isvariable("inventory[services][$(svc_idx)][only_if]");

      "svc_onlyif[$(svc_idx)]"
        string => "any",
        unless => isvariable("inventory[services][$(svc_idx)][only_if]");

      # Map the normalized service name onto the bundle that knows
      # how to configure it. Services the policy doesn't recognize
      # resolve to "" and are never run.
      "bundle_name[$(svc_idx)]"
        string => ifelse(strcmp("$(svc_canon[$(svc_idx)])", "nginx"),         "svc_nginx",
                          strcmp("$(svc_canon[$(svc_idx)])", "postgresql"),    "svc_postgresql",
                          strcmp("$(svc_canon[$(svc_idx)])", "node_exporter"), "svc_node_exporter",
                          strcmp("$(svc_canon[$(svc_idx)])", "log_shipper"),   "svc_log_shipper",
                          strcmp("$(svc_canon[$(svc_idx)])", "backup_agent"),  "svc_backup_agent",
                          strcmp("$(svc_canon[$(svc_idx)])", "redis"),        "svc_redis",
                          "");

  classes:
      # has_<service>, defined from the normalized name so it matches
      # regardless of how the inventory cased the original name.
      "has_$(svc_canon[$(svc_idx)])";

      "is_known_$(svc_idx)"
        if => not(strcmp("$(bundle_name[$(svc_idx)])", ""));

      "maintenance"
        if => strcmp("$(inventory[maintenance])", "true");

  methods:
      # Run each known, listed service's bundle when its own only_if
      # (wrapped in parens, since "." binds tighter than "|") holds
      # and the host isn't in maintenance.
      "run_$(svc_idx)"
        usebundle => "$(bundle_name[$(svc_idx)])",
        if => "is_known_$(svc_idx).has_$(svc_canon[$(svc_idx)]).!maintenance.($(svc_onlyif[$(svc_idx)]))";

  reports:
      "maintenance mode -- skipping all services"
        if => "maintenance";
}

#######################################################

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

**inventory.json** (the example from the task, placed next to `policy.cf`):
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

Tested with `cf-agent -K -f ./policy.cf`: nginx, node-exporter, and log-shipper (weekday) configure; backup-agent correctly stays off (no postgresql, not a weekend day). Also verified: mixed-casing (`NGINX`, `PostgreSQL`, `rEdIs`) all resolve correctly, an unrecognized service name is silently skipped rather than aborting the run, and `"maintenance": true` suppresses every service bundle.