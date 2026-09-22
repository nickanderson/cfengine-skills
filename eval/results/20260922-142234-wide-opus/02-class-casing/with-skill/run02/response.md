## Answer

No, you can't make class expressions case-insensitive. CFEngine class names are always case-sensitive: `has_Nginx` and `has_nginx` are two different classes, and there's no syntax or setting to change that.

The fix is to force one casing **when you define the class**. Lowercase each service name as you read it (`string_downcase()`), then `canonify()` it, so `Nginx`, `nginx` and `NGINX` all become `has_nginx`, and `Node-Exporter` becomes `has_node_exporter`. After that, the lowercase `only_if` expressions and bundle names match on every host.

Don't try to fix it the other way by lowercasing the `only_if` expressions. They use built-in time classes that start with a capital letter, like `Monday` and `Saturday`. Lowercased, `monday` is never true, so those services would silently stop running.

## Policy

`policy.cf` (mode 600, next to `inventory.json`):

```cfengine3
body common control
{
      bundlesequence => { "inventory_classes", "inventory_services" };
}

bundle common inventory_classes
# @brief Read the inventory export and define a has_<service> class per entry.
# Class names are case-sensitive and cannot be matched case-insensitively, so
# each service name is normalized to lowercase when its class is defined.
{
  vars:
      "inv" data => readjson("$(this.promise_dirname)/inventory.json");
      "i" slist => getindices("inv[services]");

      # Normalized key per entry: "Node-Exporter" -> "node_exporter"
      "key[$(i)]" string => canonify(string_downcase("$(inv[services][$(i)][name])"));

      # only_if is a class expression and is used as-is: downcasing it would
      # break mixed-case hard classes such as Monday. Absent means "any".
      # (ifelse() can't be used here: an unresolved argument skips the call.)
      "only_if[$(i)]" string => "any";
      "only_if[$(i)]"
        string => "$(inv[services][$(i)][only_if])",
        if => isvariable("inv[services][$(i)][only_if]");

      # Services this policy has a bundle for
      "known" slist => { "nginx", "postgresql", "node_exporter",
                         "log_shipper", "backup_agent", "redis" };

  classes:
      "has_$(key[$(i)])" expression => "any";
      "known_$(known)" expression => "any";
      "inventory_maintenance" expression => strcmp("$(inv[maintenance])", "true");
}

bundle agent inventory_services
# @brief Run svc_<service> for each listed, known service whose only_if holds.
{
  vars:
      "i" slist => { @(inventory_classes.i) };

  methods:
      # Parenthesize the data-supplied expression before combining it.
      # known_ guard: usebundle on a nonexistent bundle aborts the run.
      "svc_$(inventory_classes.key[$(i)])"
        usebundle => "svc_$(inventory_classes.key[$(i)])",
        if => and("!inventory_maintenance",
                  canonify("known_$(inventory_classes.key[$(i)])"),
                  canonify("has_$(inventory_classes.key[$(i)])"),
                  "($(inventory_classes.only_if[$(i)]))");
}

bundle agent svc_nginx         { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_postgresql    { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_node_exporter { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_log_shipper   { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_backup_agent  { reports: "CONFIGURED: $(this.bundle)"; }
bundle agent svc_redis         { reports: "CONFIGURED: $(this.bundle)"; }
```

`inventory.json` is your example export, saved as-is.

**How it works:**
- **Names from the inventory** are lowercased and canonified when their `has_` class is defined, so any casing works.
- **`only_if` expressions** are used exactly as written. Each one is wrapped in parentheses before it's combined with the maintenance check; otherwise `!maintenance.a|b` would mean `(!maintenance.a)|b`.
- **Services the policy has no bundle for** are skipped. Calling a bundle that doesn't exist would stop the whole agent run.
- **Maintenance** blocks every service bundle when `"maintenance": true`.

**Test results** (`cf-agent -K -f ./policy.cf`, run on a Tuesday):
- **Your example file:** printed `CONFIGURED: svc_nginx`, `svc_node_exporter` and `svc_log_shipper`. Backup-Agent was correctly skipped because the host doesn't list postgresql and it isn't the weekend.
- **Second test file** with `NGINX`, `PostgreSQL`, an unknown service, and `Redis` with `only_if: "!has_nginx"`: printed `svc_nginx` and `svc_postgresql` only.
- **Same file with `"maintenance": true`:** printed nothing.

One limit: this only fixes casing in the service names. If the inventory team writes `has_Nginx` inside an `only_if`, it still won't match. Those expressions have to use the lowercase class names.