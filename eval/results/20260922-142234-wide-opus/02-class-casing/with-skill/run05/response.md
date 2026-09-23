No, class expressions can't be made case-insensitive. CFEngine class names are always case-sensitive, and no setting or expression syntax changes that. `has_Nginx` and `has_nginx` are two separate classes.

**The fix is to normalize the name when the class is created, not when it's tested.** The policy runs each inventory name through `string_downcase()` and `canonify()` before defining the class. `Nginx`, `nginx` and `NGINX` all become `has_nginx`, and `Node-Exporter` becomes `has_node_exporter`, which also gives the bundle name `svc_node_exporter`. Since the `has_*` classes are now always lowercase, the lowercase `only_if` expressions match without any change.

Don't lowercase the `only_if` expressions themselves. They use built-in time classes like `Monday`, which have capital letters, and lowercasing would turn them into `monday`, which is never true.

A few other choices in the policy:
- **Grouping:** each `only_if` is wrapped in parentheses before it's combined with the maintenance check. Without them, an expression like `a|b` would read as `(!maintenance.a)|b`, and `b` alone could run the bundle during maintenance.
- **Unknown services:** only the six known service names can run a bundle. Calling a bundle that doesn't exist would stop the whole agent run, so an unknown entry like `Memcached` is simply ignored.
- **Duplicates:** there is one `run_<service>` class per service. If the same service is listed twice with different casing, its bundle still runs only once.

**Testing:** `cf-promises` and `cfengine lint` both pass. I ran `cf-agent -K -f ./policy.cf` against the example data on a Tuesday. It printed `svc_nginx`, `svc_node_exporter` and `svc_log_shipper`, and `svc_backup_agent` stayed off because its condition is weekend-only.
- With `POSTGRESQL`, an unknown `Memcached`, and a `NODE-EXPORTER` entry whose `only_if` needs Nginx (which wasn't listed), only `svc_postgresql` and `svc_backup_agent` ran.
- With `"maintenance": true`, nothing ran.

`policy.cf` (in the working directory, mode 600):

```cfengine3
body common control
{
      bundlesequence => { "inventory", "services" };
}

bundle common inventory
# @brief Read the inventory export and define normalized service classes.
#
# Class names are case-sensitive and cannot be matched case-insensitively,
# so every service name is forced to lowercase (and canonified) as the
# class is defined: "Nginx", "nginx" and "NGINX" all define has_nginx.
{
  vars:
      "data" data => readjson("$(this.promise_dirname)/inventory.json");
      "i" slist => getindices("data[services]");

      # Normalized service name, e.g. "Node-Exporter" -> "node_exporter"
      "svc[$(i)]"
        string => canonify(string_downcase("$(data[services][$(i)][name])"));

      # The only_if expression is used as-is; an entry without one always holds.
      "only_if[$(i)]"
        string => "$(data[services][$(i)][only_if])",
        if => isvariable("data[services][$(i)][only_if]");
      "only_if[$(i)]"
        string => "any",
        unless => isvariable("data[services][$(i)][only_if]");

  classes:
      "inventory_maintenance"
        expression => regcmp("(?i)true", "$(data[maintenance])");

      "has_$(svc[$(i)])"
        expression => "any";

      # Parenthesize the data-supplied expression so a top-level | in it
      # cannot escape the maintenance guard.
      "run_$(svc[$(i)])"
        expression => "!inventory_maintenance.($(only_if[$(i)]))";
}

bundle agent services
# @brief Run the bundle of every known service the inventory selected.
{
  vars:
      # Only services with a bundle below; anything else in the inventory is
      # ignored (usebundle on a nonexistent bundle would abort the run).
      "known" slist => { "nginx", "postgresql", "node_exporter",
                         "log_shipper", "backup_agent", "redis" };

  methods:
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

`inventory.json` (the example export, saved next to the policy):

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

One limit: the names inside `only_if` are used exactly as written, so the inventory team still has to write them in lowercase with underscores, such as `has_node_exporter` rather than `has_Node-Exporter`.