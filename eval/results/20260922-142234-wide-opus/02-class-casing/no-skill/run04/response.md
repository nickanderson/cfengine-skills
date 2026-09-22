**Short answer: no.** CFEngine class names and class expressions are always case-sensitive. `has_Nginx` and `has_nginx` are two different classes, and there's no flag or function that makes an expression match regardless of case.

The fix is to lowercase the data before it becomes a class name. The policy runs each inventory name through `string_downcase()` and then `canonify()`. So `Nginx`, `nginx` and `NGINX` all become `has_nginx`, and `Node-Exporter` becomes `has_node_exporter`. Once the names are normalized, the lowercase `only_if` expressions and bundle names match.

I did **not** lowercase the `only_if` expressions themselves. They refer to built-in classes like `Monday` and `Saturday`, which are also case-sensitive and capitalized, so lowercasing them would break them. The deal with the inventory team should be: service names can be cased any way you like, but `only_if` must use lowercase `has_*` names, as it does now.

I ran it with `cf-agent -K -f ./policy.cf` on a Tuesday against the example inventory, and it configured nginx, node_exporter and log_shipper. backup_agent was skipped, as expected, because it needs postgresql and a weekend day. With `"maintenance": true` nothing ran. When I changed the first entry to `"POSTGRESQL"`, postgresql, node_exporter and log_shipper ran.

One thing to know: cf-agent refused to run the policy while `policy.cf` was writable by others, so I had to `chmod 600` it first.

### `policy.cf`
```cfengine3
body common control
{
      bundlesequence => { "main" };
}

bundle agent main
# Read the per-host inventory, normalise service names to lowercase
# canonical form, define has_<service> classes and run the matching
# svc_<service> bundles.
{
  vars:
      # Services this policy knows how to configure (svc_<name> bundles).
      "known_services"
        slist => { "nginx", "postgresql", "node_exporter",
                   "log_shipper", "backup_agent", "redis" };

      "inventory"
        data => readjson("$(this.promise_dirname)/inventory.json");

      "i" slist => getindices("inventory[services]");

      # Class names are case-sensitive, so normalise the data instead:
      # "Node-Exporter", "node-exporter", "NODE-EXPORTER" -> "node_exporter"
      "service[$(i)]"
        string => canonify(string_downcase("$(inventory[services][$(i)][name])"));

      # only_if is used verbatim: it may reference hard classes such as
      # Monday, which are themselves case-sensitive and must not be downcased.
      "only_if[$(i)]"
        string => "$(inventory[services][$(i)][only_if])",
        if => isvariable("inventory[services][$(i)][only_if]");
      "only_if[$(i)]"
        string => "any",
        unless => isvariable("inventory[services][$(i)][only_if]");

  classes:
      "inventory_maintenance"
        expression => strcmp("true", string_downcase("$(inventory[maintenance])"));

      # Defined for every listed service first, so that only_if expressions
      # evaluated below can reference any of them regardless of list order.
      "has_$(service[$(i)])"
        expression => "any",
        scope => "namespace";

      "run_$(service[$(i)])"
        expression => "has_$(service[$(i)]).($(only_if[$(i)]))",
        unless => "inventory_maintenance";

  methods:
      "$(known_services)"
        usebundle => "svc_$(known_services)",
        if => "run_$(known_services)";
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

### `inventory.json` (example)
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

How it works:
- **Order doesn't matter:** all `has_*` classes are defined before any `run_*` class is checked. An `only_if` can therefore refer to a service listed later in the inventory.
- **Maintenance:** `maintenance` is also lowercased before it's checked, so `true` or `"True"` both block every service bundle.
- **Only known bundles run:** the methods promise loops over a fixed list of known services. An unknown service in the inventory (say `"Memcached"`) does nothing instead of calling a bundle that doesn't exist. Anything not listed, like `svc_redis` here, never runs.