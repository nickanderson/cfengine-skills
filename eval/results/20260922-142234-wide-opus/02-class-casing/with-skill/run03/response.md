## Can class expressions be case-insensitive?

No. CFEngine class names are always case-sensitive, and no flag or expression syntax changes that. `has_Nginx`, `has_nginx` and `has_NGINX` are three different classes. That's why hosts whose inventory says `Nginx` never matched your lowercase bundles and `only_if` expressions.

The fix is to change the name to one casing **when you define the class**, not when you test it. The policy lowercases each inventory name and turns anything that isn't a letter, digit or underscore into `_` (`canonify`). So `Nginx`, `nginx` and `NGINX` all become `has_nginx`, and `Node-Exporter` becomes `has_node_exporter`. Your `only_if` expressions and bundle names are already lowercase, so they then match.

Don't try it the other way round by lowercasing the `only_if` expressions. They can refer to built-in classes that are mixed case, like `Monday`. Lowercasing `has_postgresql.(Saturday|Sunday)` turns it into `...(saturday|sunday)`, which is never true.

## What I tested

`cf-promises` and `cfengine lint` both pass, and `cf-agent -K -f ./policy.cf` runs. Today is a Tuesday, and with the example inventory it prints:

```
R: CONFIGURED: svc_nginx
R: CONFIGURED: svc_node_exporter
R: CONFIGURED: svc_log_shipper
```

`svc_backup_agent` doesn't run: it needs `has_postgresql` and a weekend. I also changed the inventory to check a few other cases:
- **`PostgreSQL` instead of `Nginx`:** runs `svc_postgresql`, `svc_node_exporter` and `svc_log_shipper`.
- **Maintenance set to `true`:** nothing runs.
- **`NGINX` plus an unknown `Unknown-Thing` entry:** the same output as the example, and the unknown entry is ignored.

## How it works

- **Unknown services are skipped safely.** The policy loops over its own list of the six bundles it has, not over the inventory entries. An inventory entry with no matching bundle is ignored instead of calling a bundle that doesn't exist, which would stop the whole agent run.
- **`only_if` is checked after all `has_*` classes exist.** The `has_*` classes are set in a first bundle, and the `run_<service>` classes are worked out in a second one. So `only_if: "has_nginx|has_postgresql"` gets the right answer whatever order the entries are in.
- **`only_if` is used exactly as written, in parentheses.** The parentheses keep the inventory team's `a|b` from mixing with the policy's own conditions. An entry with no `only_if` always counts as true.
- **One gotcha I hit:** my first version used `ifelse()` to supply the default for a missing `only_if`. It failed silently for entries with no `only_if` key, and `svc_nginx` never ran. Two separate definitions, a default of `"any"` and an override when the key exists, fixed it.

## Files

Both files are in the working directory, set to mode 600 because `cf-agent` refuses policy files that others can write to.

**inventory.json**
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

**policy.cf**
```cfengine3
body common control
{
      bundlesequence => { "inventory_classes", "inventory_services" };
}

bundle common inventory_classes
# @brief Read the inventory export and define one has_<service> class per
# listed service. Class names are case-sensitive and cannot be matched
# case-insensitively, so the service name is normalized (lowercased and
# canonified) at the point where the class is defined.
{
  vars:
      "inv"
        data => readjson("$(this.promise_dirname)/inventory.json");

      "idx"
        slist => getindices("inv[services]");

      # "Node-Exporter" -> "node_exporter"
      "svc[$(idx)]"
        string => canonify(string_downcase("$(inv[services][$(idx)][name])"));

      # The only_if expression is used as written (not downcased, since it may
      # reference mixed-case hard classes such as Monday). Parenthesized so it
      # combines safely with other conditions. Absent means always true. (Two
      # promises rather than ifelse(): ifelse() is not evaluated when one of its
      # arguments references a key that does not exist.)
      "cond[$(idx)]"
        string => "any";

      "cond[$(idx)]"
        string => "($(inv[services][$(idx)][only_if]))",
        if => isvariable("inv[services][$(idx)][only_if]");

  classes:
      "has_$(svc[$(idx)])"
        expression => "any";

      "inventory_maintenance"
        expression => strcmp("true", "$(inv[maintenance])");
}

bundle agent inventory_services
# @brief Run the bundle for each known service that the host lists, whose
# only_if holds, when the host is not in maintenance.
{
  vars:
      # Services this policy knows how to configure (bundle svc_<name>).
      "known"
        slist => { "nginx", "postgresql", "node_exporter",
                   "log_shipper", "backup_agent", "redis" };

  classes:
      # Evaluated after inventory_classes has finished, so every has_* class
      # referenced by an only_if expression is already defined.
      "run_$(inventory_classes.svc[$(inventory_classes.idx)])"
        expression => "$(inventory_classes.cond[$(inventory_classes.idx)])";

  methods:
    !inventory_maintenance::
      # Iterate over known names only, so an unknown inventory entry can never
      # produce a usebundle reference to a bundle that does not exist.
      "svc_$(known)"
        usebundle => "svc_$(known)",
        if => canonify("run_$(known)");
}

bundle agent svc_nginx
{
  reports:
      "CONFIGURED: $(this.bundle)";
}

bundle agent svc_postgresql
{
  reports:
      "CONFIGURED: $(this.bundle)";
}

bundle agent svc_node_exporter
{
  reports:
      "CONFIGURED: $(this.bundle)";
}

bundle agent svc_log_shipper
{
  reports:
      "CONFIGURED: $(this.bundle)";
}

bundle agent svc_backup_agent
{
  reports:
      "CONFIGURED: $(this.bundle)";
}

bundle agent svc_redis
{
  reports:
      "CONFIGURED: $(this.bundle)";
}
```

One thing the policy can't fix: the `only_if` expressions have to keep using lowercase `has_*` names. If the inventory team ever writes `has_Nginx` in an `only_if`, it will never match.