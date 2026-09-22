**No, you can't make them case-insensitive.** In CFEngine, class names and class expressions are always case-sensitive, and no setting changes that. `has_Nginx` and `has_nginx` are two different classes. The fix is to normalise the data before it becomes a class: trim each inventory service name, lowercase it with `string_downcase()`, then `canonify()` it. That way `Nginx`, `nginx`, `NGINX` and ` NGINX ` all become `has_nginx`, and `Node-Exporter` becomes `has_node_exporter`.

Two design points:

- **The `only_if` expressions are not lowercased.** They can contain built-in classes whose names are mixed case by design (`Monday`, `Hr08`, `Yr2026`). Lowercasing would break those. The inventory team's lowercase `has_<service>` names in `only_if` are fine, because the classes they refer to are now always lowercase.
- **All `has_*` classes are defined before any `only_if` is checked.** That's done in a separate, earlier bundle, so an entry can refer to a service listed after it. For example, `Backup-Agent` can come before `PostgreSQL` in the list.

I ran it with CFEngine 3.27.1 on a Tuesday:
- **Example inventory:** `svc_nginx`, `svc_node_exporter` and `svc_log_shipper` ran. `svc_backup_agent` didn't, because `has_postgresql.(Saturday|Sunday)` is false here.
- **Mixed-case test:** `" POSTGRESQL "`, a `Backup-Agent` whose `only_if` refers to the later `postgresql` entry, `REDIS` with `only_if: has_nginx` but no nginx, and an unknown service. Only `svc_postgresql` and `svc_backup_agent` ran.
- **`"maintenance": true`:** no service bundles ran.

Some behaviours to know about:
- A service the policy has no bundle for is ignored.
- An `only_if` that is empty or malformed evaluates to false, so that service won't run.
- `cf-agent` refused to run `policy.cf` while other users could write to it (a security check), so I ran `chmod 600` on it.

Files written: `policy.cf` and `inventory.json` (the example export).

```cfengine3
# Inventory-driven service configuration.
#
# CFEngine class names and class expressions are always case-sensitive;
# there is no switch to change that. So we normalise the *data* instead:
# every service name from the inventory is trimmed, lowercased and
# canonified before it is turned into a class, i.e.
#   "Nginx", "nginx", "NGINX"  -> has_nginx
#   "Node-Exporter"            -> has_node_exporter
#
# The only_if expressions are NOT lowercased: they may contain hard
# classes that are mixed case by design (Monday, Hr08, Yr2026, ...).
# They are expected to reference has_<service> classes in lowercase.

body common control
{
      bundlesequence => { "main" };
}

bundle agent main
{
  methods:
      # Define every has_<service> class first, so that only_if expressions
      # can refer to any service regardless of its position in the list.
      "inventory_classes" usebundle => inventory_classes("$(this.promise_dirname)/inventory.json");
      "inventory_services" usebundle => inventory_services;
}

bundle agent inventory_classes(file)
{
  vars:
      "inv" data => readjson("$(file)");
      "idx" slist => getindices("inv[services]");

      # trim -> lowercase -> canonify
      "name[$(idx)]"
        string => canonify(string_downcase(regex_replace("$(inv[services][$(idx)][name])", "^\s+|\s+$", "", "g")));

  classes:
      "has_$(name[$(idx)])"
        expression => "any",
        scope => "namespace";

      # JSON booleans expand to "true"/"false"; accept any casing of "true".
      "inventory_maintenance"
        expression => regcmp("(?i)true", "$(inv[maintenance])"),
        scope => "namespace";

  reports:
    inventory_maintenance::
      "Host is in maintenance, no services will be configured";
}

bundle agent inventory_services
{
  vars:
      # Services this policy knows how to configure (bundle svc_<name>).
      "known" slist => { "nginx", "postgresql", "node_exporter",
                         "log_shipper", "backup_agent", "redis" };

      "idx" slist => { @(inventory_classes.idx) };
      "name[$(idx)]" string => "$(inventory_classes.name[$(idx)])";

      # Condition that must hold: only_if if present, otherwise always.
      "cond[$(idx)]"
        string => "$(inventory_classes.inv[services][$(idx)][only_if])",
        if => isvariable("inventory_classes.inv[services][$(idx)][only_if]");
      "cond[$(idx)]"
        string => "any",
        if => not(isvariable("inventory_classes.inv[services][$(idx)][only_if]"));

  classes:
    !inventory_maintenance::
      "run_$(name[$(idx)])"
        expression => "$(cond[$(idx)])";

  methods:
      "svc_$(known)"
        usebundle => "svc_$(known)",
        if => "run_$(known)";
}

bundle agent svc_nginx         { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_postgresql    { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_node_exporter { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_log_shipper   { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_backup_agent  { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_redis         { reports: "CONFIGURED: $(this.bundle)"; }
```

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