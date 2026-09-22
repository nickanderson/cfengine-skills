Clean. Both files are in place and verified with `cf-agent -K -f ./policy.cf`.

## Summary

Class expressions themselves can't be made case-insensitive — CFEngine class matching is always case-sensitive with no override. The fix is to normalize casing once, at the point the class is *defined* (`string_downcase()` + `canonify()` on the inventory's service name), so `has_nginx` is always the class regardless of whether the inventory said `Nginx`, `nginx`, or `NGINX`. Bundles and `only_if` expressions then keep using plain lowercase names as before.

**`policy.cf`:**
```cfengine3
body common control
{
      bundlesequence => { "inventory", "main" };
}

# Reads the per-host service inventory and turns it into two things every
# other bundle relies on: a has_<service> class per listed service, and an
# only_if[<service>] lookup of the class expression (if any) that must also
# hold. Classes are case-sensitive and cannot be matched case-insensitively,
# so the inventory's casing (Nginx / nginx / NGINX) is normalized here, once,
# when the class is defined -- everything downstream can stay lowercase.
bundle common inventory
{
  vars:
      "data"
        data => readjson("$(this.promise_dirname)/inventory.json");

      "idx"
        slist => getindices("data[services]");

      "raw_name[$(idx)]"
        string => "$(data[services][$(idx)][name])";

      "norm_name[$(idx)]"
        string => canonify(string_downcase("$(raw_name[$(idx)])"));

      # have_only_if_$(idx) (defined below) isn't known until pass 2; until
      # then these two promises are simply skipped, which is harmless since
      # they're recomputed every pass.
      "only_if[$(norm_name[$(idx)])]"
        string => "$(data[services][$(idx)][only_if])",
        if => "have_only_if_$(idx)";

      "only_if[$(norm_name[$(idx)])]"
        string => "any",
        unless => "have_only_if_$(idx)";

  classes:
      "has_$(norm_name[$(idx)])"
        expression => "any";

      "maintenance"
        expression => strcmp(string_downcase("$(data[maintenance])"), "true");

      # ifelse()/isvariable() can't be used directly for this: function
      # arguments are expanded eagerly, so referencing a missing
      # data[...][only_if] key inside the unused branch would still make the
      # whole promise unresolvable. A guard class sidesteps that.
      "have_only_if_$(idx)"
        expression => isvariable("data[services][$(idx)][only_if]");
}

bundle agent main
{
  vars:
      "known_services"
        slist => { "nginx", "postgresql", "node_exporter", "log_shipper", "backup_agent", "redis" };

      # Default to "any" for known services the inventory doesn't mention at
      # all, or mentions without an only_if. See bundle inventory for why
      # this needs a guard class rather than ifelse()/isvariable().
      "only_if_expr[$(known_services)]"
        string => "$(inventory.only_if[$(known_services)])",
        if => "have_only_if_$(known_services)";

      "only_if_expr[$(known_services)]"
        string => "any",
        unless => "have_only_if_$(known_services)";

  classes:
      "have_only_if_$(known_services)"
        expression => isvariable("inventory.only_if[$(known_services)]");

  methods:
      "configure $(known_services)"
        usebundle => "svc_$(known_services)",
        if => "has_$(known_services).!maintenance.($(only_if_expr[$(known_services)]))";
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

**`inventory.json`** (example, matching the one in the prompt):
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

Notes on things I hit and fixed while testing:
- An `ifelse(isvariable(...), "$(maybe-missing-key)", "default")` pattern doesn't work for optional JSON keys — CFEngine expands function arguments eagerly, so the unused branch's reference to a missing key still poisons the whole promise. Replaced with a guard-class pair (`if`/`unless`) instead.
- `only_if` values are used as-is (parenthesized), since they already reference correctly-cased hard classes (`Monday`) and already-normalized `has_*` classes.
- Verified against mixed casing (`NGINX`, `nOdE-eXpOrTeR`), `maintenance: true`, and the original example — all produced the expected `CONFIGURED:` set with no extraneous bundles run.