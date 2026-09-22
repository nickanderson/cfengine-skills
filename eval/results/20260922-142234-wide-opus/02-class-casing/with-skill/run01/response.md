**No, you can't.** CFEngine class names are always case-sensitive, and no syntax, flag or setting changes that. `has_Nginx`, `has_nginx` and `has_NGINX` are three separate classes. The fix is to **normalize the value when you define the class**. Run each inventory name through `string_downcase()` and `canonify()` (so `Node-Exporter`, `NODE-EXPORTER` and `node_exporter` all become `node_exporter`). Then define `has_<that>` and run `svc_<that>`. Your lowercase bundles and `only_if` expressions will then always match.

Don't lowercase the `only_if` expressions themselves. They can reference hard classes that are mixed case, such as `Monday` or `Saturday`. Lowercasing `has_postgresql.(Saturday|Sunday)` would turn it into `...(saturday|sunday)`, which is never true. Use those expressions exactly as written, and put them in parentheses before combining them with your own conditions.

## `inventory.json`

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

## `policy.cf`

```cfengine3
body common control
{
      bundlesequence => { "inventory_services" };
}

bundle agent inventory_services
# @brief Define has_<service> classes from inventory.json and run the matching
# svc_<service> bundles. Service names are normalized to lowercase (and
# canonified) when the class is defined, because class matching is always
# case-sensitive.
{
  vars:
      "inv"
        data => readjson("$(this.promise_dirname)/inventory.json");

      "i"
        slist => getindices("inv[services]");

      # Service bundles this policy knows how to configure. Anything else in
      # the inventory is ignored (usebundle on an unknown name aborts the run).
      "known_bundles"
        slist => { "svc_nginx", "svc_postgresql", "svc_node_exporter",
                   "svc_log_shipper", "svc_backup_agent", "svc_redis" };

      # "Node-Exporter", "node-exporter", "NODE_EXPORTER" -> "node_exporter"
      "_svc[$(i)]"
        string => canonify(string_downcase("$(inv[services][$(i)][name])"));

      "_bundle[$(i)]"
        string => "svc_$(_svc[$(i)])";

      # only_if is used as-is: lowercasing it would break mixed-case hard
      # classes such as Monday. Parenthesize it before combining.
      "_only_if[$(i)]"
        string => "any";
      "_only_if[$(i)]"
        string => "$(inv[services][$(i)][only_if])",
        if => isvariable("inv[services][$(i)][only_if]");

  classes:
      "maintenance"
        expression => strcmp("true", "$(inv[maintenance])");

      "has_$(_svc[$(i)])"
        expression => "any";

      "_known_$(i)"
        expression => some("^$(_bundle[$(i)])$", known_bundles);

  methods:
    !maintenance::
      "$(_bundle[$(i)])"
        usebundle => "$(_bundle[$(i)])",
        if => "_known_$(i).($(_only_if[$(i)]))";

  reports:
    maintenance::
      "Host is in maintenance; no service bundles run";
}

bundle agent svc_nginx         { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_postgresql    { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_node_exporter { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_log_shipper   { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_backup_agent  { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_redis         { reports: "CONFIGURED: $(this.bundle)"; }
```

## Test results

The policy passes `cf-promises -cf`. Running `cf-agent -K -f ./policy.cf` on a Tuesday against the example export printed:

```
R: CONFIGURED: svc_nginx
R: CONFIGURED: svc_node_exporter
R: CONFIGURED: svc_log_shipper
```

`svc_backup_agent` correctly didn't run: the host doesn't list PostgreSQL, and it isn't the weekend.

I also tested it with other inventory files:
- **Mixed casing and an unknown service** (`NGINX`, `PostgreSQL`, `Memcached`, lowercase `backup-agent`): nginx, postgresql and backup_agent ran. Memcached was skipped without error.
- **Redis with a false `only_if`:** the Redis entry required `has_nginx.!has_postgresql`, which was false on that host, so it didn't run.
- **Maintenance on** (`"maintenance": true`): no service bundles ran.
- **Condition not met:** an `only_if` that references services the host doesn't list ran nothing.

## Notes

- **Names the policy doesn't know are skipped.** Each normalized name is checked against `known_bundles` before calling `usebundle`. A name that matches no bundle would stop the whole agent run.
- **`only_if` is taken literally.** The policy doesn't change the casing inside these expressions, so the inventory team must write them in lowercase `has_<service>` form, with underscores in place of hyphens (for example `has_node_exporter`). Hard classes keep their normal casing.

Both `policy.cf` and `inventory.json` are in the working directory, with mode 600.