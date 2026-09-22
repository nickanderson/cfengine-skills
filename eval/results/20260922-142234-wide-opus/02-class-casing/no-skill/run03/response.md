**No, you can't make class expressions case-insensitive in CFEngine.** Class names are case-sensitive and there's no option to change that. `has_Nginx` and `has_nginx` are two different classes. Built-in classes like `Monday` and `Saturday` are case-sensitive too.

The fix is to normalise the inventory value before it becomes a class name. The policy lower-cases each service name with `string_downcase()`, then runs `canonify()` to turn characters that can't appear in a class name into `_`. So `Nginx`, `nginx` and `NGINX` all become `has_nginx`, and `Node-Exporter` becomes `has_node_exporter`. After that, your lowercase bundle names and `only_if` expressions match.

The `only_if` expressions are left exactly as written, because lower-casing them would turn `Monday` into `monday`, which never matches. That means the inventory team still needs to write the `has_…` names in lowercase. That's already what they do, and it's easy to lint in the export.

### `policy.cf`

```cfengine
body common control
{
      bundlesequence => { "main" };
}

bundle agent main
# @brief Configure the services the inventory lists for this host.
#
# CFEngine class names and class expressions are case-sensitive, and there is
# no switch to make them case-insensitive. So instead of trying to match
# loosely, we normalise the inventory data *before* it becomes a class:
# every service name is lower-cased and canonified ("Node-Exporter" ->
# "node_exporter"), so the has_<service> classes are always lowercase and
# match the lowercase names used by the bundles and the only_if expressions.
#
# The only_if expressions are deliberately NOT lower-cased: they may refer
# to hard classes such as Monday or Saturday, which are themselves
# case-sensitive and capitalised.
{
  vars:
      "inventory"
        data => readjson( "$(this.promise_dirname)/inventory.json" );

      "i" slist => getindices( "inventory[services]" );

      # Normalised service name for each inventory entry
      "service[$(i)]"
        string => canonify( string_downcase( "$(inventory[services][$(i)][name])" ) );

      # The inventory team's condition, only for entries that carry one
      "only_if[$(i)]"
        string => "$(inventory[services][$(i)][only_if])",
        if => isvariable( "inventory[services][$(i)][only_if]" );

      # Services this policy knows how to configure (bundle svc_<name>)
      "known" slist => { "nginx", "postgresql", "node_exporter",
                         "log_shipper", "backup_agent", "redis" };

  classes:
      "maintenance"
        expression => strcmp( "true", "$(inventory[maintenance])" ),
        scope => "namespace";

      # has_<service> for every listed service, always lowercase
      "has_$(service[$(i)])"
        expression => "any",
        scope => "namespace";

      # run_<service>: listed, and its only_if (if any) holds
      "run_$(service[$(i)])"
        expression => "any",
        unless => isvariable( "only_if[$(i)]" );

      "run_$(service[$(i)])"
        expression => "$(only_if[$(i)])",
        if => isvariable( "only_if[$(i)]" );

  methods:
    !maintenance::
      "Configure $(known)"
        usebundle => "svc_$(known)",
        if => "run_$(known)";

  reports:
    maintenance::
      "Host is in maintenance; no services configured";
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

### `inventory.json` (your example)

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

### Test results (CFEngine 3.27.1, `cf-agent -K -f ./policy.cf`, on a Tuesday)

**Your example inventory:**
```
R: CONFIGURED: svc_nginx
R: CONFIGURED: svc_node_exporter
R: CONFIGURED: svc_log_shipper
```
`svc_backup_agent` correctly didn't run: there's no PostgreSQL and it isn't the weekend.

**A second inventory with mixed casing and an unknown service.** It listed `POSTGRESQL`, `ReDis` and an unknown `Unknown-Thing`. `Node-Exporter` came before the service its `only_if` depends on, and `Backup-Agent` had `Tuesday` added to its `only_if`:
```
R: CONFIGURED: svc_postgresql
R: CONFIGURED: svc_node_exporter
R: CONFIGURED: svc_backup_agent
R: CONFIGURED: svc_redis
```
- The odd casing still matched.
- The unknown service was ignored.
- The order of entries in the list doesn't matter.

**The same inventory with `"maintenance": true`:** no service bundles ran, only the maintenance report.

Both files are in the working directory.