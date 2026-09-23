**Short answer: no.** CFEngine class names and class expressions are always case-sensitive, and there's no setting or function that changes that. `has_Nginx` and `has_nginx` are two different classes. Hard classes are affected too: `Monday` matches, `monday` doesn't.

The fix is to lowercase the data before you turn it into class names. The policy passes each service name through `string_downcase()` and then `canonify()`, so `Nginx`, `nginx` and `NGINX` all become `has_nginx`, and `Node-Exporter` becomes `has_node_exporter`. The bundle names and the lowercase `has_*` names in `only_if` then match.

I don't lowercase the `only_if` expressions themselves. Doing that would break capitalised hard classes like `Monday` and `Saturday`. So the rule for the inventory team is: inside `only_if`, refer to services by their lowercase, canonified name (e.g. `has_node_exporter`). Their example export already does this.

**`policy.cf`**
```cfengine
body common control
{
      bundlesequence => { "main" };
}

bundle agent main
# @brief Define lowercase has_<service> classes from inventory and run the
# matching service bundles.
#
# Class names are case-sensitive in CFEngine, so the service names are
# normalized (string_downcase + canonify) before the classes are defined.
# The only_if expressions are used as written; they are expected to refer to
# the normalized, lowercase has_<service> classes.
{
  vars:
      "inventory"
        data => readjson("$(this.promise_dirname)/inventory.json");

      "i"
        slist => getindices("inventory[services]");

      # "Node-Exporter", "NODE-EXPORTER", "node-exporter" -> "node_exporter"
      "service[$(i)]"
        string => canonify(string_downcase("$(inventory[services][$(i)][name])"));

      # Condition that must also hold; "any" when only_if is absent.
      "only_if[$(i)]"
        string => "$(inventory[services][$(i)][only_if])",
        if => isvariable("inventory[services][$(i)][only_if]");
      "only_if[$(i)]"
        string => "any",
        if => not(isvariable("inventory[services][$(i)][only_if]"));

      # Service bundles this policy knows how to configure.
      "known"
        slist => { "nginx", "postgresql", "node_exporter",
                   "log_shipper", "backup_agent", "redis" };

  classes:
      "maintenance"
        expression => strcmp("true", "$(inventory[maintenance])");

      "has_$(service[$(i)])"
        expression => "any";

      "run_$(service[$(i)])"
        expression => "$(only_if[$(i)])";

  methods:
      "svc_$(known)"
        usebundle => "svc_$(known)",
        if => "run_$(known).!maintenance";

  reports:
    maintenance::
      "Host is in maintenance; no services configured.";
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

**`inventory.json`** (your example export, for testing)
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

**How it works**
- A service's bundle runs only if all three hold: the host lists the service (`run_<svc>` is set), its `only_if` is true (`any` when there isn't one), and the host is not in maintenance.
- `methods` only loops over the six bundles the policy knows. Any other service in the inventory is ignored, so there are no calls to bundles that don't exist.
- `run_<svc>` can depend on another service's `has_*` class, and the order of entries in the list doesn't matter.

**Test results** with CFEngine 3.27.1, running `cf-agent -K -f ./policy.cf` (today is Tuesday):
- **Example as given** (and again with `NGINX`): nginx, node_exporter and log_shipper were configured. backup_agent was not, because there's no postgresql and it isn't the weekend.
- **Name changed to `POSTGRESQL`, run with `-D Sunday`:** postgresql, node_exporter, log_shipper and backup_agent were configured. log_shipper still ran because the real Tuesday class is also set.
- **`"maintenance": true`:** no service bundles ran. Only the maintenance message was reported.

cf-agent refused to run the policy until I made it non-world-writable (`chmod 600 policy.cf`), so keep that permission when you deploy it.