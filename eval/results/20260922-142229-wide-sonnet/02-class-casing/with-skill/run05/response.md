## Answer

CFEngine class names and expressions are case-sensitive with no flag to switch that off — `has_nginx` and `has_Nginx` are permanently different classes. But you don't need case-insensitive *matching*: normalize the casing once, at the point where you *define* the presence class from the inventory value (`canonify(string_downcase(name))`), and have every downstream reference — bundle names, `only_if` expressions — consistently use that same lowercase form. Since the `only_if` expressions already reference lowercase class names like `has_nginx`, this one-time normalization fixes matching everywhere.

One gotcha hit along the way: a CFEngine `vars:` promise whose right-hand side interpolates a variable/data-container key that doesn't exist for that iteration (e.g. entries without `only_if`) is left **unresolved and silently never defined**, not set to an empty string. The fix is to gate the interpolating promise with a class guard (`if =>` / `unless =>`) so the lookup is only attempted when the key is actually present.

## Policy

`policy.cf`:
```cfengine3
body common control
{
      bundlesequence => { "main" };
}

bundle agent main
# Reads the per-host service inventory and runs the bundle for each service
# the host lists, subject to its "only_if" class expression and the global
# maintenance flag.
{
  vars:
      "inventory"
        data => readjson("$(this.promise_dirname)/inventory.json");

      "idx"
        slist => getindices("inventory[services]");

      # The only services this policy knows how to configure, and the
      # bundle that configures each one.
      "known_bundle"
        data => '{
          "nginx": "svc_nginx",
          "postgresql": "svc_postgresql",
          "node_exporter": "svc_node_exporter",
          "log_shipper": "svc_log_shipper",
          "backup_agent": "svc_backup_agent",
          "redis": "svc_redis"
        }';

      # Canonical name per inventory entry: lowercased and canonified, so
      # "Nginx", "nginx" and "NGINX" all resolve to the same class/bundle.
      "canon[$(idx)]"
        string => canonify(string_downcase("$(inventory[services][$(idx)][name])"));

  classes:
      # Case-insensitive presence class: whatever casing the inventory used
      # for this entry's name, this always defines the same canonical class.
      "has_$(canon[$(idx)])";

      "in_maintenance"
        expression => strcmp("$(inventory[maintenance])", "true");

      # Only services we have a bundle for get run; anything else in the
      # inventory is silently ignored.
      "known_$(idx)"
        expression => isvariable("known_bundle[$(canon[$(idx)])]");

      # Guards which of the two only_if_expr promises below fires. Needed
      # because interpolating a key that doesn't exist in this entry (most
      # entries have no only_if) leaves the variable promise unresolved
      # rather than empty, so the lookup must be skipped entirely for
      # entries that carry no only_if.
      "has_only_if_$(idx)"
        expression => isvariable("inventory[services][$(idx)][only_if]");

  vars:
      # An entry's own only_if, parenthesized so it combines safely with
      # "!in_maintenance" below ("." binds tighter than "|").
      "only_if_expr[$(idx)]"
        string => "($(inventory[services][$(idx)][only_if]))",
        if => "has_only_if_$(idx)";

      # No only_if on this entry: it always qualifies.
      "only_if_expr[$(idx)]"
        string => "any",
        unless => "has_only_if_$(idx)";

      "run_if[$(idx)]"
        string => "!in_maintenance.$(only_if_expr[$(idx)])";

  methods:
      "known_$(idx)"::
      "svc_$(idx)"
        usebundle => "$(known_bundle[$(canon[$(idx)])])",
        if => "$(run_if[$(idx)])";
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

`inventory.json` (the example from the prompt, written next to the policy):
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

Verified with `cf-promises -cf ./policy.cf` and `cf-agent -K -f ./policy.cf`, including variants with mixed-case names (`NGINX`, `postgresql`, `Redis`, `backup-agent`), an unrecognized service name (silently ignored), and `maintenance: true` (suppresses everything).