**No, you can't make class expressions case-insensitive.** CFEngine class names are case-sensitive, and no syntax, flag or setting changes that. `has_Nginx` and `has_nginx` are two different classes.

The fix is to normalize the name when you define the class, not when you test it. If the policy runs the inventory name through `string_downcase()` and `canonify()` as it creates the class, then `Nginx`, `nginx` and `NGINX` all define `has_nginx`, and `Node-Exporter` defines `has_node_exporter`. Your lowercase bundles and `only_if` expressions then match on every host.

Two things to avoid:
- **Don't downcase the `only_if` expressions.** They also use CFEngine's built-in day-of-week classes, which are mixed case (`Monday`). Lowercasing the expression turns that into `monday`, which is never true. Use the expressions exactly as the inventory team wrote them.
- **Always run names through `canonify()`, not just `string_downcase()`.** A `classes:` promise quietly turns `has_Node-Exporter` into a valid name. A class *expression* doesn't: the `-` is read as part of the expression, so it never matches.

## The policy

`policy.cf`:

```cfengine3
body common control
{
      bundlesequence => { "inventory_classes", "inventory_services" };
}

bundle common inventory_classes
# @brief Read the inventory export and define a has_<service> class per entry.
#
# Class names are case-sensitive and nothing makes class expressions
# case-insensitive, so the inventory value is normalized to lowercase (and
# canonified) when the class is defined: Nginx, nginx and NGINX all define
# has_nginx, and Node-Exporter defines has_node_exporter.
{
  vars:
      "inv" data => readjson("$(this.promise_dirname)/inventory.json");
      "i" slist => getindices("inv[services]");

      # Normalized service name per inventory entry
      "svc[$(i)]"
        string => canonify(string_downcase("$(inv[services][$(i)][name])"));

      # only_if is used as-is. It is not downcased: that would break
      # mixed-case hard classes such as Monday.
      "cond[$(i)]"
        string => "$(inv[services][$(i)][only_if])",
        if => isvariable("inv[services][$(i)][only_if]");
      "cond[$(i)]"
        string => "any",
        unless => isvariable("inv[services][$(i)][only_if]");

  classes:
      "has_$(svc[$(i)])"
        comment => "Host lists this service in the inventory";

      "inventory_maintenance"
        expression => strcmp(string_downcase("$(inv[maintenance])"), "true"),
        comment => "Host is in maintenance; configure no services";
}

bundle agent inventory_services
# @brief Run the bundle for each known service the host lists, when its
# only_if holds and the host is not in maintenance.
{
  vars:
      # Services this policy has a svc_<name> bundle for
      "known" slist => { "nginx", "postgresql", "node_exporter",
                         "log_shipper", "backup_agent", "redis" };

      "i" slist => { @(inventory_classes.i) };

  classes:
      # Evaluated here, after inventory_classes has defined every has_*
      # class, so only_if can refer to any service on the host. The data
      # supplied expression is parenthesized before combining it with ours.
      "run_$(inventory_classes.svc[$(i)])"
        if => "has_$(inventory_classes.svc[$(i)]).!inventory_maintenance.($(inventory_classes.cond[$(i)]))";

  methods:
      # Iterating over the known list (not the inventory) means usebundle
      # always names an existing bundle, and each runs at most once.
      "svc_$(known)"
        usebundle => "svc_$(known)",
        if => "run_$(known)";
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

`inventory.json` (your example export):

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

## How it works
- **All the `has_*` classes are defined first**, in their own bundle. An `only_if` can then refer to any service on the host, whatever order the inventory lists them in.
- **Each `only_if` is wrapped in parentheses** before being combined with the maintenance check. Without them, `.` binds tighter than `|`, so `!inventory_maintenance.has_nginx|has_postgresql` would ignore maintenance for the `has_postgresql` part.
- **The policy loops over its own list of known services, not the inventory.** So an unknown service in the inventory (say `Unknown-Thing`) is ignored instead of stopping the run on a missing bundle. Each service bundle also runs at most once, even if a host lists the same service twice in different casings. In that case the bundle runs if either entry's `only_if` holds.
- **An entry with no `only_if` counts as always true.** A missing `maintenance` key counts as not in maintenance.

## Test results
Both files are written with mode 600. `cf-promises` and `cfengine lint` pass, and I ran `cf-agent -K -f ./policy.cf` against several inventories. The test day was a Tuesday.

| Inventory | Output |
|---|---|
| Your example export | `svc_nginx`, `svc_node_exporter`, `svc_log_shipper` (not `svc_backup_agent`: no postgresql, and not a weekend) |
| `POSTGRESQL`, `Backup-Agent` with `only_if` `has_postgresql.Tuesday`, `REDIS`, `Unknown-Thing` | `svc_postgresql`, `svc_backup_agent`, `svc_redis`; the unknown service was ignored |
| `"maintenance": true` with `Nginx` | nothing |
| No `maintenance` key, `nginx`, and `Redis` with `only_if` `has_postgresql` | `svc_nginx` only |

After testing I put your original example back in `inventory.json`.