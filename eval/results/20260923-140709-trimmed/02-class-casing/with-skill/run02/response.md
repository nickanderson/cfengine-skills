## Answer

CFEngine class expressions are always case-sensitive, and there's no global switch to change that (hard classes like `Monday` are intentionally mixed-case, so a blanket "make it case-insensitive" toggle doesn't exist).

The fix is to normalize the casing exactly once, at the single point where the class name is *defined* — not in the expressions that *test* it. So the inventory-team's `only_if` text and your bundles' `has_<service>` references should stay lowercase (as they already are); you just need the policy that turns an inventory entry's `name` field into a `has_<service>` class to canonicalize the name first: `string_downcase(canonify($(name)))`. `Nginx`, `nginx`, and `NGINX` all normalize to `has_nginx`, so every casing variant now defines the same class the rest of the policy already expects.

## Policy

Wrote `policy.cf` and `inventory.json` to the working directory. It reads the inventory, defines `has_<service>` per entry (name normalized), and `run_<service>` when the service is listed, its `only_if` (if any) holds, and the host isn't in maintenance — then runs exactly the six known service bundles, gated on those `run_*` classes. Verified with `cf-promises --full-check` and several `cf-agent -K -f ./policy.cf` runs (the given example, mixed-cased names, and a maintenance=true case).

```cfengine3
#######################################################
#
# Run per-host services from an inventory export, tolerating
# any casing ("Nginx" / "nginx" / "NGINX") in the service names.
#
# CFEngine class expressions are always case-sensitive and that
# cannot be switched off. Instead of trying to match the inventory
# text as-is, we normalize each service name to a canonical
# lowercase class suffix *once*, at the point where the has_<service>
# class is defined, and leave the "only_if" expressions themselves
# untouched -- they reference those already-normalized has_* classes
# plus mixed-case hard classes (Monday, Tuesday, ...) that must keep
# their original casing to match.
#
#######################################################

body common control
{
      bundlesequence => { "main" };
}

#######################################################

bundle agent main
{
  methods:
      "load_inventory"  usebundle => inventory_data;

      "nginx"          usebundle => svc_nginx,          if => "run_nginx";
      "postgresql"     usebundle => svc_postgresql,     if => "run_postgresql";
      "node_exporter"  usebundle => svc_node_exporter,  if => "run_node_exporter";
      "log_shipper"    usebundle => svc_log_shipper,    if => "run_log_shipper";
      "backup_agent"   usebundle => svc_backup_agent,   if => "run_backup_agent";
      "redis"          usebundle => svc_redis,          if => "run_redis";
}

#######################################################

bundle common inventory_data
# Reads inventory.json, defines has_<service> for every listed
# service (name normalized to lowercase/canonical form), and
# run_<service> when that service should actually be configured:
# listed, its own only_if (if any) holds, and the host is not
# in maintenance.
{
  vars:
      "raw" data => readjson("$(this.promise_dirname)/inventory.json", 1000000);

      "service_idx" slist => getindices("raw[services]");

      "service_name[$(service_idx)]"
        string => "$(raw[services][$(service_idx)][name])";

      # Normalize once, here, where the class is defined -- never
      # normalize a whole class expression later.
      "service_class[$(service_idx)]"
        string => string_downcase(canonify("$(service_name[$(service_idx)])"));

      # Keys present on this entry ("name", or "name" + "only_if").
      # Looking this up avoids interpolating a "[only_if]" path that
      # doesn't exist on entries that omit it, which would otherwise
      # leave the whole promise unresolved.
      "service_keys[$(service_idx)]"
        slist => getindices("raw[services][$(service_idx)]");

      "service_key_count[$(service_idx)]"
        int => length("service_keys[$(service_idx)]");

      "service_only_if[$(service_idx)]"
        string => "any";

      # Only pull in "only_if" once we know it exists -- and gate on
      # a function result (not a separately defined class), so this
      # resolves entirely within the vars phase of pass 1, before
      # anything downstream reads it.
      "service_only_if[$(service_idx)]"
        string => "$(raw[services][$(service_idx)][only_if])",
        if => strcmp("$(service_key_count[$(service_idx)])", "2");

  classes:
      "maintenance"
        expression => "any",
        if => strcmp("$(raw[maintenance])", "true");

      "has_$(service_class[$(service_idx)])"
        expression => "any";

    !maintenance::

      # The "only_if" text is itself a class expression (e.g.
      # "has_nginx|has_postgresql", possibly combined with hard
      # classes like "Monday"). Substituting it straight into the
      # expression attribute parses and evaluates it as one, so the
      # day-name classes keep whatever casing CFEngine itself uses
      # for them.
      "run_$(service_class[$(service_idx)])"
        expression => "$(service_only_if[$(service_idx)])";
}

#######################################################
# Service bundle stubs
#######################################################

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

With the example inventory (today being a weekday, no `postgresql` entry), running `cf-agent -K -f ./policy.cf` correctly configures `nginx`, `node_exporter`, and `log_shipper`, and skips `backup_agent` since its `only_if` needs `has_postgresql`.