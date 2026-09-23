Clean run, no errors. `policy.cf` and `inventory.json` are in place in the working directory.

## Answer

No — CFEngine class expressions are always case-sensitive; there's no flag or syntax to make `.`/`|`/`!` matching case-insensitive. `has_nginx`, `has_Nginx`, and `has_NGINX` are three distinct, unrelated classes.

The fix isn't to make matching case-insensitive, it's to make the *data* consistent before it becomes a class name. Case-fold each inventory service name (`string_downcase(canonify(name))`) at the single point where the `has_<service>` class is defined, so `Nginx`/`nginx`/`NGINX` all collapse to the same `has_nginx` class. Leave the `only_if` expressions written by the inventory team untouched — don't downcase the whole expression, because it legitimately mixes your lowercase `has_*` names with mixed-case hard classes like `Monday`/`Tuesday`, which must keep their real casing to match at all.

One gotcha I hit while testing: within a single evaluation pass, when two different `vars` promises target the same variable, the *later* one (in source order) wins, not the first. I initially had a "default `only_if` = any" promise after the per-entry assignment, which silently clobbered real `only_if` expressions back to `any`. Fixed by putting the default-fill first and the per-entry (inventory-derived) assignment after it.

I validated the policy with `cf-promises --full-check` and by running `cf-agent -K -f ./policy.cf` against several inventories: the exact example, one mixing `NGINX`/`postgresql`/`node-exporter`/an unrecognized service name, and one with `maintenance: true` — in each case only the correct bundles ran.

```cfengine3
body common control
{
      bundlesequence => { "main" };
}

bundle agent main
# Reads inventory.json (list of services + per-service `only_if` class
# expressions, written by the inventory team) and runs the matching
# svc_* bundle for each service the host is supposed to run.
{
  vars:
      "inv"
        data => readjson("$(this.promise_dirname)/inventory.json", 1M);

      "idx"
        slist => getindices("inv[services]");

      "known_services"
        slist => { "nginx", "postgresql", "node_exporter", "log_shipper", "backup_agent", "redis" };

      # Inventory casing ("Nginx", "nginx", "NGINX", ...) is folded to a
      # canonical lower-case form *here*, at the single point where the
      # has_<service> class name is derived from data. This is the only
      # place case-folding belongs -- class expressions themselves stay
      # case-sensitive (CFEngine has no case-insensitive matching mode),
      # and the `only_if` expressions below are used verbatim: they
      # legitimately mix our lower-case has_* class names with mixed-case
      # hard classes such as Monday/Tuesday.
      "canon[$(idx)]"
        string => string_downcase(canonify("$(inv[services][$(idx)][name])"));

      # Default only_if => "any" for every known service, so the `if`
      # expressions below always interpolate to something syntactically
      # valid even when a service is absent from the inventory (its
      # has_<service> class will be undefined anyway, so it still won't run).
      # This must be assigned *before* the per-entry values below: within
      # a single pass, unguarded vars promises evaluate in source order and
      # a later assignment to the same variable overwrites an earlier one.
      "only_if[$(known_services)]"
        string => "any";

      # Per-entry only_if, defaulting to "any" when the entry has none.
      # Keyed by canonical name so it can be looked up per known service
      # below. Runs after the default fill above so an inventory-supplied
      # value overwrites the blanket default for services actually present.
      "only_if[$(canon[$(idx)])]"
        string => ifelse(isvariable("inv[services][$(idx)][only_if]"),
                          "$(inv[services][$(idx)][only_if])",
                          "any");

  classes:
      "maintenance"
        expression => ifelse(strcmp("$(inv[maintenance])", "true"), "any", "!any");

      "has_$(canon[$(idx)])"
        expression => "any";

  methods:
      "nginx"
        usebundle => svc_nginx,
        if => "has_nginx.(!maintenance).($(only_if[nginx]))";

      "postgresql"
        usebundle => svc_postgresql,
        if => "has_postgresql.(!maintenance).($(only_if[postgresql]))";

      "node_exporter"
        usebundle => svc_node_exporter,
        if => "has_node_exporter.(!maintenance).($(only_if[node_exporter]))";

      "log_shipper"
        usebundle => svc_log_shipper,
        if => "has_log_shipper.(!maintenance).($(only_if[log_shipper]))";

      "backup_agent"
        usebundle => svc_backup_agent,
        if => "has_backup_agent.(!maintenance).($(only_if[backup_agent]))";

      "redis"
        usebundle => svc_redis,
        if => "has_redis.(!maintenance).($(only_if[redis]))";
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

A note on the six `methods` promises being spelled out explicitly rather than looped: `usebundle` doesn't accept a computed bundle name safely for arbitrary/unknown services — if inventory ever lists a service with no matching bundle, a dynamic `usebundle => "svc_$(canon)"` would abort the whole agent run. Enumerating the known services keeps unknown inventory entries (like `UNKNOWN-THING` in my test) harmless no-ops instead.