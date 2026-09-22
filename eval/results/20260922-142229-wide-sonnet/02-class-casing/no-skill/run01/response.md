Matches expectations exactly for the example inventory (today is a Tuesday, no postgresql listed, so `backup_agent` correctly stays off).

## Answer

No — CFEngine's class-expression algebra (`.`, `|`, `!` used in `expression`/`ifvarclass`) matches class names by **exact string**, and there's no case-fold option anywhere in that evaluation. `has_nginx` and `has_Nginx` are simply different class names to CFEngine.

The fix is to normalize once, at the source: when turning an inventory entry into a `has_<service>` class, lower-case and canonify the name (`canonify(string_downcase(name))`) before building the class name string. Since your bundles and the inventory team's `only_if` expressions are already written in lowercase, normalizing at that single point makes the whole chain casing-proof — `Nginx`, `nginx`, and `NGINX` all collapse to the same `has_nginx` class.

## Policy

```cf3
#
# Runs per-host service bundles based on an inventory export that may spell
# service names with inconsistent casing (Nginx / nginx / NGINX ...).
#
# CFEngine class expressions (the |, ., ! algebra used in `expression` and
# `ifvarclass`) match class names by exact string -- there is no way to make
# that matching case-insensitive. Instead, every service name coming out of
# inventory.json is normalized (lower-cased + canonified) exactly once, at
# the point where the has_<service> class is defined. Everything downstream
# -- our own bundles and the inventory team's only_if expressions -- already
# uses lowercase canonical names, so normalizing at the source is enough to
# make the whole chain casing-proof.
#

body common control
{
      bundlesequence => { "main" };
}

bundle agent main
{
  vars:
      "inv"          data  => readjson("$(this.promise_dirname)/inventory.json", "1000000");
      "maintenance"  string => "$(inv[maintenance])";

      "idx" slist => getindices("inv[services]");

      "svc_canon[$(idx)]"
        string => canonify(string_downcase("$(inv[services][$(idx)][name])"));

      # Known service -> stub bundle map. Any inventory entry whose
      # normalized name isn't a key here simply has no bundle to run.
      "known_bundle[nginx]"         string => "svc_nginx";
      "known_bundle[postgresql]"    string => "svc_postgresql";
      "known_bundle[node_exporter]" string => "svc_node_exporter";
      "known_bundle[log_shipper]"   string => "svc_log_shipper";
      "known_bundle[backup_agent]"  string => "svc_backup_agent";
      "known_bundle[redis]"         string => "svc_redis";

      # Left unresolved (and therefore undefined) for entries with no
      # matching stub bundle -- guarded against below with isvariable().
      "bundle_name[$(idx)]" string => "$(known_bundle[$(svc_canon[$(idx)])])";

  classes:
      "in_maintenance" expression => strcmp(string_downcase("$(maintenance)"), "true");

      # Must be defined before the only_if_ok_$(idx) promises below run, so
      # they can gate on it within the same pass (class promises in one
      # classes: block are evaluated top to bottom).
      "has_only_if_$(idx)" expression => isvariable("inv[services][$(idx)][only_if]");

      # Presence class: defined case-insensitively for every service the
      # host lists, exactly once, normalized to lowercase.
      "has_$(svc_canon[$(idx)])" expression => "any";

      # An entry with no only_if is unconditionally ok to run. This is done
      # as two class promises (not a vars default) because classes are
      # monotonic -- re-evaluating them each pass is safe -- whereas a vars
      # promise locks in whatever value it gets on its first successful
      # pass, which would wrongly latch "any" before has_only_if_$(idx) is
      # known.
      "only_if_ok_$(idx)"
        expression => "$(inv[services][$(idx)][only_if])",
        ifvarclass => "has_only_if_$(idx)";

      "only_if_ok_$(idx)"
        expression => "any",
        ifvarclass => "!has_only_if_$(idx)";

      "bundle_known_$(idx)" expression => isvariable("bundle_name[$(idx)]");

      "run_$(idx)"
        expression => "has_$(svc_canon[$(idx)]).only_if_ok_$(idx).!in_maintenance";

  methods:
      "configure service $(idx)"
        usebundle  => "$(bundle_name[$(idx)])",
        ifvarclass => "run_$(idx).bundle_known_$(idx)";
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

Along with the example `inventory.json` in the same directory:

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

Verified with `cf-agent -K -f ./policy.cf` (CFEngine 3.27.1): the base inventory correctly runs `svc_nginx`, `svc_node_exporter`, and `svc_log_shipper` (today is Tuesday) while skipping `svc_backup_agent` (no `postgresql` present). I also tested mixed casing (`NGINX`, `PostgreSQL`, `node-exporter`, `Redis`) — all matched correctly — an unlisted service name (silently skipped, no error), and `"maintenance": true` (suppresses every bundle).

One implementation note worth flagging: an earlier version used a `vars` promise with an `ifvarclass` guard to default missing `only_if` to `"any"`. That's a trap — CFEngine variables latch their first successfully-assigned value, so on the first convergence pass (before the gating class was known) it wrongly locked in `"any"` for every service, including ones with a real `only_if`. Encoding the default as two `classes` promises instead fixed it, since classes are monotonic and safe to re-evaluate.