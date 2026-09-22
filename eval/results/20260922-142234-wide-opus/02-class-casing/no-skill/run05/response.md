**Short answer: no.** CFEngine class names and class expressions are always case-sensitive, and there is no setting or function that makes them match case-insensitively. `has_Nginx` and `has_nginx` are two different classes. The fix is to clean up the data instead. Before a service name becomes a class, lowercase it with `string_downcase()` and then run it through `canonify()`. `Nginx`, `nginx` and `NGINX` all become `has_nginx`, and `Node-Exporter` becomes `has_node_exporter`, which matches your bundle names.

**Don't lowercase the `only_if` expressions.** They can refer to built-in classes like `Monday` or `Saturday`, which are mixed case, so lowercasing them would stop those from ever matching. The policy uses them exactly as written. That's safe as long as they refer to services with lowercase `has_<service>` names, which yours already do.

I ran it with `cf-agent -K -f ./policy.cf` (CFEngine 3.27.1) on a Tuesday:

- **Example inventory:** `svc_nginx`, `svc_node_exporter` and `svc_log_shipper` ran. `svc_backup_agent` did not, because its `only_if` needs PostgreSQL and a weekend.
- **Name `NGINX` with `"maintenance": true`:** nothing ran.
- **Name `postgreSQL`:** `svc_postgresql`, `svc_node_exporter` and `svc_log_shipper` ran.

`inventory.json` is back to the example contents. I had to `chmod 600 policy.cf` first, because cf-agent refuses to run a policy file that other users can write to.

**`inventory.json`**
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

**`policy.cf`**
```cfengine3
# CFEngine class names and class expressions are case-sensitive; there is no
# case-insensitive matching mode. So instead of matching loosely we normalize
# the inventory data: every service name is lowercased and canonified
# ("Node-Exporter" -> "node_exporter") before it becomes a has_<service> class.
#
# The only_if expressions are used verbatim. They must NOT be lowercased,
# because they may reference hard classes that are mixed case (Monday,
# Saturday, ...). They refer to services via the lowercase has_<service>
# names, which is exactly what we define here.

body common control
{
      bundlesequence => { "inventory_services" };
}

bundle agent inventory_services
{
  vars:
      "inv"
        data => readjson("$(this.promise_dirname)/inventory.json", 1M);

      "i" slist => getindices("inv[services]");

      # Normalized service name, e.g. "Node-Exporter" -> "node_exporter"
      "name[$(i)]"
        string => canonify(string_downcase("$(inv[services][$(i)][name])"));

      # Condition that must also hold; defaults to "any" when absent
      "only_if[$(i)]"
        string => "$(inv[services][$(i)][only_if])",
        if => isvariable("inv[services][$(i)][only_if]");
      "only_if[$(i)]"
        string => "any",
        unless => isvariable("inv[services][$(i)][only_if]");

      # Services this policy knows how to configure (bundle svc_<name>)
      "known" slist => { "nginx", "postgresql", "node_exporter",
                         "log_shipper", "backup_agent", "redis" };

  classes:
      # JSON boolean true (or the string "true", any casing) enables maintenance
      "maintenance"
        expression => strcmp("true", string_downcase("$(inv[maintenance])")),
        scope => "namespace";

      # All has_ classes are defined first, so any only_if may refer to them
      "has_$(name[$(i)])"
        expression => "any",
        scope => "namespace";

      "run_$(name[$(i)])"
        expression => "$(only_if[$(i)])",
        scope => "namespace";

  methods:
    !maintenance::
      "svc_$(known)"
        usebundle => "svc_$(known)",
        if => "has_$(known).run_$(known)";
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

How it behaves:
- **Only known bundles run.** The methods loop goes over the six known services, not the inventory list. A service in the inventory with no matching bundle is ignored, and so is anything the host doesn't list.
- **Missing `only_if` means no extra condition.** An entry without one is treated as always true.
- **Order doesn't matter.** Every `has_*` class is defined before any `only_if` is checked, so an `only_if` can refer to a service listed later in the file.
- **The same service listed twice:** if two entries become the same name (say `Nginx` and `nginx`), the bundle runs when either entry's `only_if` is true.
- **Mixed-case `only_if` still fails.** An expression like `has_Nginx` won't match. Ask the inventory team to always use lowercase, canonified names in `only_if`.