Confirmed working. Both files are in place at `/tmp/cfeval-02-class-casing-with-skill.TeMciD8k/work/`.

## Answer

CFEngine class names and class expressions are always case-sensitive — there is no flag, operator, or syntax that makes matching case-insensitive. `has_nginx` and `has_Nginx` are simply different classes.

The fix is to normalize once, at the single point where inventory data becomes a class: `canonify(string_downcase(name))`. Every `has_<service>` class the policy defines is then always lowercase, no matter how the inventory spelled it (`Nginx`, `nginx`, `NGINX` all collapse to `has_nginx`). Everything downstream — bundle names, `only_if` expressions — only ever needs to know about that one canonical form.

Importantly, the `only_if` expression itself must **not** be blanket-lowercased: it also references mixed-case hard classes like `Monday`/`Tuesday`. Downcasing the whole expression would silently turn `Monday` into `monday`, which never matches. So only the value being turned into a class is normalized; expressions are used verbatim (just parenthesized, since `.` binds tighter than `|` and the expression is being combined with other conditions).

## Policy

`policy.cf`:
```cfengine3
#############################################################################
# Runs the service bundle for every service the inventory export lists for
# this host, provided:
#   - the host is not in maintenance
#   - the entry's own "only_if" class expression (if any) is true
#
# Inventory casing is unreliable ("Nginx" / "nginx" / "NGINX" all show up),
# and CFEngine class names/expressions are always case-sensitive -- there is
# no case-insensitive matching mode. So every service name is normalized
# with canonify(string_downcase(...)) at the single point where it becomes
# a has_<service> class; everything downstream (bundles, only_if
# expressions) only ever deals with that one canonical lowercase form.
#
# The "only_if" expression itself is used verbatim: it is written by the
# inventory team against our lowercase has_<service> convention, but it also
# references mixed-case hard classes (Monday, Tuesday, ...), so it must NOT
# be case-folded as a whole -- only the has_<service> classes it tests are
# normalized, at definition time.
#############################################################################

body common control
{
      bundlesequence => { "main" };
}

bundle agent main
{
  vars:
      "inv" data => readjson("$(this.promise_dirname)/inventory.json", "1M");

      "service_idx" slist => getindices("inv[services]");

      # Normalize each listed service name once: canonify + lowercase.
      "service_key[$(service_idx)]"
        string => canonify(string_downcase("$(inv[services][$(service_idx)][name])"));

      # Keyed by the normalized service name -- first definition wins per
      # key, which is fine since each service should appear once. Default
      # a missing only_if to "any", without disturbing the expression's
      # own casing when it is present.
      "only_if[$(service_key[$(service_idx)])]"
        string => ifelse(
          isvariable("inv[services][$(service_idx)][only_if]"),
          "$(inv[services][$(service_idx)][only_if])",
          "any");

      # One lookup per bundle we know how to run. isvariable() falls back
      # to "any" for a known service that simply wasn't in the inventory
      # (its has_<service> class won't be defined either, so the guard
      # below still keeps the bundle from running).
      "only_if_nginx"         string => ifelse(isvariable("only_if[nginx]"),         "$(only_if[nginx])",         "any");
      "only_if_postgresql"    string => ifelse(isvariable("only_if[postgresql]"),    "$(only_if[postgresql])",    "any");
      "only_if_node_exporter" string => ifelse(isvariable("only_if[node_exporter]"), "$(only_if[node_exporter])", "any");
      "only_if_log_shipper"   string => ifelse(isvariable("only_if[log_shipper]"),   "$(only_if[log_shipper])",   "any");
      "only_if_backup_agent"  string => ifelse(isvariable("only_if[backup_agent]"),  "$(only_if[backup_agent])",  "any");
      "only_if_redis"         string => ifelse(isvariable("only_if[redis]"),         "$(only_if[redis])",         "any");

  classes:
      "maintenance"
        if => strcmp("$(inv[maintenance])", "true");

      # service_key is already canonified/lowercased, so has_<key> is a
      # stable, case-normalized class no matter how the inventory spelled
      # the service name.
      "has_$(service_key[$(service_idx)])"
        if => "any";

  methods:
      "nginx"
        usebundle => svc_nginx,
        if => "has_nginx.!maintenance.($(only_if_nginx))";

      "postgresql"
        usebundle => svc_postgresql,
        if => "has_postgresql.!maintenance.($(only_if_postgresql))";

      "node_exporter"
        usebundle => svc_node_exporter,
        if => "has_node_exporter.!maintenance.($(only_if_node_exporter))";

      "log_shipper"
        usebundle => svc_log_shipper,
        if => "has_log_shipper.!maintenance.($(only_if_log_shipper))";

      "backup_agent"
        usebundle => svc_backup_agent,
        if => "has_backup_agent.!maintenance.($(only_if_backup_agent))";

      "redis"
        usebundle => svc_redis,
        if => "has_redis.!maintenance.($(only_if_redis))";
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

`inventory.json` (the example from the prompt, written alongside `policy.cf`):
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

Tested with `cf-promises --full-check` and `cf-agent -K -f ./policy.cf`: the stock inventory runs `svc_nginx`, `svc_node_exporter`, and `svc_log_shipper` (today is a Tuesday, so the weekday clause holds), and correctly skips `svc_postgresql`/`svc_backup_agent`/`svc_redis`. I also verified `NGINX`/`postgreSQL` casing variants resolve to the same classes, an unrecognized service name in the inventory is silently ignored, and `"maintenance": true` suppresses all service bundles.