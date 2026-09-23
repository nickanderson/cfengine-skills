## Is case-insensitive class matching possible?

Not directly — CFEngine class name matching is an exact string comparison; there's no "ignore case" flag for `expression`, `if`, `ifvarclass`, or `only_if`-style class expressions. (Each atom in a class expression *is* matched as a regex against defined classes, so you could hand-write `[Nn][Gg][Ii][Nn][Xx]` per service, but that's brittle and doesn't scale to arbitrary casing like `NGINX`.)

The robust fix is to normalize *once*, at the point where data becomes a class: case-fold (and canonify, for names like `Node-Exporter`) the inventory `name` before building the `has_<service>` class name. Then every casing variant of `Nginx`/`nginx`/`NGINX` collapses onto the same class `has_nginx`, which lines up with the lowercase names the inventory team already writes in `only_if` expressions and that the bundles already use. No change to `only_if` authoring conventions is needed.

## Implementation notes

A couple of non-obvious CFEngine mechanics drove the structure:
- A `data`-typed variable can't be assigned to an array-indexed name (`"entry[$(idx)]"` is rejected) — so each inventory entry is handed off to a small helper bundle (`declare_has`/`declare_run`) instead of building indexed containers in `main`.
- Passing a data container across a bundle call requires the fully-qualified reference (`"main.inv[services][$(idx)]"`), materialized locally with `mergedata()` — a bare reference doesn't resolve across bundle scope.
- `classes:` promises default to bundle-local scope; `scope => "namespace"` is required for `has_<service>`/`run_<service>`/`maintenance` to be visible where they're used afterward.
- Processing happens in two explicit passes (`has_$(idx)` for all entries, then `run_$(idx)` for all entries) so an `only_if` like `has_nginx|has_postgresql` can rely on *every* `has_*` class already being defined, regardless of array order in the JSON.

Verified with `cf-agent -K -f ./policy.cf` against the given sample, and against a mutated inventory with `NGINX`/`PostgreSQL`/`node-exporter` casing, a forced `Saturday` class (to exercise `Backup-Agent`'s weekend `only_if`), and `maintenance: true` (confirmed it suppresses every service bundle).

```cfengine3
#
# Inventory-driven service configuration.
#
# Class *matching* in CFEngine is exact-string / case-sensitive; there is no
# "case-insensitive class expression" mode to flip on. So instead of trying
# to make `only_if` expressions tolerant of casing, this policy normalizes
# each inventory service name (downcase + canonify) once, at the single
# point where the `has_<service>` class gets defined. That guarantees
# "Nginx", "nginx" and "NGINX" all collapse onto the same class: has_nginx.
# Because has_<service> classes always end up lowercase/canonical, the
# `only_if` expressions written by the inventory team (already lowercase,
# e.g. "has_nginx|has_postgresql") line up correctly no matter how the
# source "name" field was cased on a given host.
#
body common control
{
      bundlesequence => { "main" };
}

bundle agent main
{
    vars:
        "inv" data  => readjson("$(this.promise_dirname)/inventory.json", "1M");
        "idx" slist => getindices("inv[services]");

    classes:
        # Host is in maintenance mode -> no service bundles should run.
        "maintenance"
            expression => "any",
            scope      => "namespace",
            if         => strcmp("$(inv[maintenance])", "true");

    methods:
        # Pass 1: define has_<service> for every inventoried service, with
        # the name case-folded/canonicalized, regardless of source casing.
        "has_$(idx)" usebundle => declare_has("main.inv[services][$(idx)]");

        # Pass 2: now that all has_<service> classes exist, evaluate each
        # entry's only_if (defaulting to "any" when absent) to decide
        # whether to actually configure the service.
        "run_$(idx)" usebundle => declare_run("main.inv[services][$(idx)]");

        # Only ever call the bundles we know about, and only when the
        # inventory-driven run_<service> class says so.
        "nginx"         usebundle => svc_nginx,         ifvarclass => "run_nginx";
        "postgresql"    usebundle => svc_postgresql,    ifvarclass => "run_postgresql";
        "node_exporter" usebundle => svc_node_exporter, ifvarclass => "run_node_exporter";
        "log_shipper"   usebundle => svc_log_shipper,   ifvarclass => "run_log_shipper";
        "backup_agent"  usebundle => svc_backup_agent,  ifvarclass => "run_backup_agent";
        "redis"         usebundle => svc_redis,         ifvarclass => "run_redis";
}

bundle agent declare_has(entry_ref)
{
    vars:
        "entry" data   => mergedata("$(entry_ref)");

        # Case-fold + canonify: "Nginx" / "nginx" / "NGINX" / "Node-Exporter"
        # all normalize to the same has_<...> class name.
        "canon" string => canonify(string_downcase("$(entry[name])"));

    classes:
        "has_$(canon)"
            expression => "any",
            scope      => "namespace";
}

bundle agent declare_run(entry_ref)
{
    vars:
        "defaults" data   => parsejson('{"only_if":"any"}');
        "entry"    data   => mergedata("$(entry_ref)");
        "merged"   data   => mergedata("defaults", "entry");
        "canon"    string => canonify(string_downcase("$(entry[name])"));
        "only_if"  string => "$(merged[only_if])";

    classes:
        "run_$(canon)"
            expression => "has_$(canon).($(only_if)).!maintenance",
            scope      => "namespace";
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

Both files are written to the working directory (`policy.cf`, `inventory.json`) and run standalone via `cf-agent -K -f ./policy.cf`.