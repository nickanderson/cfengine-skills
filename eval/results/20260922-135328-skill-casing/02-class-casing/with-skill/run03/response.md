Both files are in place and the policy runs cleanly standalone.

## Answer

No — CFEngine class expressions are case-sensitive with no flag or syntax to turn that off. `role_batch` and `role_Batch` are different classes, permanently.

The fix isn't to make matching case-insensitive; it's to normalize the value **once, at the point the class is defined**, so `Nginx`, `nginx`, and `NGINX` all collapse onto the same class name (`has_nginx`) regardless of how the inventory wrote it. The `only_if` expressions written by the inventory team don't need touching — they already reference `has_<service>` in lowercase, and they reference hard classes like `Monday` in their native mixed case, so they're evaluated as-is against the now-consistently-named classes.

I built and ran the policy in `/tmp/cfeval-02-class-casing-with-skill.4HXqQFpH/work/`, verifying (via `cf-promises -cf` and several `cf-agent -K` runs) that `NGINX`, `nginx`, and mixed-case names all fold into the same class, that `maintenance: true` suppresses every bundle, and that an unlisted service name is filtered out by a whitelist rather than crashing the run.

One non-obvious pitfall I hit and fixed along the way: computing the `only_if` default with `ifelse(isvariable(...), ..., "any")` silently dropped the whole promise for entries with no `only_if`, because `ifelse`'s unused branch is still evaluated and referencing a nonexistent JSON path aborted that iteration. Switched to `mergedata('{"only_if":"any"}', ...)` so a default is always present before it's read.

```cfengine3
########################################################################
# Runs the service bundle matching each entry in inventory.json.
#
# CFEngine classes are case-sensitive with no way to switch that off, and
# inventory data comes in with inconsistent casing ("Nginx", "nginx",
# "NGINX", ...). The fix is not to make class *expressions* case-insensitive
# (not possible) but to normalize the value once, at the point where the
# has_<service> class is defined, so it always lands on the same lowercase
# class name regardless of how the inventory wrote it. The only_if
# expressions written by the inventory team already reference has_<service>
# in lowercase, and reference hard classes (Monday, ...) in their native
# mixed case, so they are used as-is -- only the defining side needs
# normalization.
########################################################################

body common control
{
      bundlesequence => { "main" };
}

bundle agent main
{
  vars:
      "inv"
        data => readjson("$(this.promise_dirname)/inventory.json");

      "service_idx"
        slist => getindices("inv[services]");

      # Bundles this policy knows how to run. A service whose normalized
      # name isn't in this list is reported by inventory but never acted
      # on -- "run no other service bundles".
      "known_services"
        slist => { "nginx", "postgresql", "node_exporter", "log_shipper", "backup_agent", "redis" };

      # Default to an always-true expression when an entry carries no
      # only_if, so the guard below can always parenthesize a value.
      # (mergedata rather than ifelse(isvariable(...), ...): ifelse's
      # true-branch argument is evaluated even when unused, and referencing
      # a data path that doesn't exist for entries without only_if drops
      # the whole promise iteration instead of yielding an empty string.)
      "svc_$(service_idx)"
        data => mergedata('{"only_if":"any"}', "inv[services][$(service_idx)]");

  classes:
      # Normalize the casing once, where the class is defined: whatever
      # casing the inventory used ("Nginx", "NGINX", "nginx", ...), this
      # always defines the same lowercase has_<service> class.
      "has_$(with)"
        with => canonify(string_downcase("$(inv[services][$(service_idx)][name])"));

      # Fixed, always-true classes for the services this policy supports,
      # used below as a whitelist check against the (normalized) inventory
      # name.
      "known_$(with)"
        with => canonify(string_downcase("$(known_services)"));

      "maintenance"
        expression => strcmp("$(inv[maintenance])", "true");

  methods:
      # Data-supplied only_if expressions are parenthesized before being
      # combined with our own classes: "." binds tighter than "|", so an
      # unparenthesized "a|b" only_if would silently attach to the wrong
      # side of "!maintenance.<expr>".
      "$(service_idx)"
        usebundle => "svc_$(with)",
        with => canonify(string_downcase("$(inv[services][$(service_idx)][name])")),
        if => "has_$(with).known_$(with).!maintenance.($(svc_$(service_idx)[only_if]))";
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

`inventory.json` (the example from the prompt, written next to `policy.cf`):

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