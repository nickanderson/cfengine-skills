All three casing variants (`NGINX`, `PostgreSQL`, `rEdIs`) correctly matched their bundles, and `maintenance: true` correctly suppressed every service. The original `inventory.json` is restored.

## Answer to the casing question

No — CFEngine class names are case-sensitive and there's no flag, operator, or mode that makes class expression matching case-insensitive. `has_nginx` and `has_Nginx` are simply different classes.

The fix is to normalize *once*, at the point where you define the class from the untrusted inventory value, rather than trying to make matching itself insensitive: `string_downcase()` + `canonify()` the service name before using it in the class name (`Node-Exporter` → `node_exporter`). As long as your bundles and the inventory team's `only_if` expressions are consistently lowercase (which they are here), everything downstream matches regardless of how the export cased the value.

## Policy

`policy.cf`:
```cfengine3
#####################################################################
# Runs the service bundle matching each service the host-inventory
# export lists, provided the entry's own "only_if" class expression
# (if any) is true and the host is not in maintenance.
#
# Class names are case-sensitive in CFEngine with no way to switch
# that off (there is no case-insensitive class-matching mode). The
# inventory's "name" field can be cased arbitrarily ("Nginx",
# "NGINX", "nginx", ...), so instead of matching it case-sensitively
# we normalize it ourselves at the point we define the has_<service>
# class: string_downcase() + canonify() turn "Node-Exporter" into
# "node_exporter" the same way "node-exporter" or "NODE-EXPORTER"
# would. The has_* classes and the "only_if" expressions written by
# the inventory team are then compared consistently in lowercase.
#####################################################################

body common control
{
      bundlesequence => { "main" };
}

#####################################################################

bundle agent main
{
  vars:
      "inventory"
        data => readjson("$(this.promise_dirname)/inventory.json", "1M");

      "service_idx"
        slist => getindices("inventory[services]");

      # Per-service "only_if" expression, keyed by the same normalized
      # name used for the has_<service> classes below. Only defined
      # when the inventory entry actually carries an "only_if" key.
      "only_if_$(with)"
        string => "$(inventory[services][$(service_idx)][only_if])",
        with   => canonify(string_downcase("$(inventory[services][$(service_idx)][name])")),
        if     => isvariable("inventory[services][$(service_idx)][only_if]");

      # Effective only_if per known service bundle: the data-supplied
      # expression if present, otherwise a class that is always true.
      "effective_only_if_nginx"
        string => ifelse(isvariable("only_if_nginx"), "$(only_if_nginx)", "any");

      "effective_only_if_postgresql"
        string => ifelse(isvariable("only_if_postgresql"), "$(only_if_postgresql)", "any");

      "effective_only_if_node_exporter"
        string => ifelse(isvariable("only_if_node_exporter"), "$(only_if_node_exporter)", "any");

      "effective_only_if_log_shipper"
        string => ifelse(isvariable("only_if_log_shipper"), "$(only_if_log_shipper)", "any");

      "effective_only_if_backup_agent"
        string => ifelse(isvariable("only_if_backup_agent"), "$(only_if_backup_agent)", "any");

      "effective_only_if_redis"
        string => ifelse(isvariable("only_if_redis"), "$(only_if_redis)", "any");

  classes:
      # Normalize the boolean from the JSON export.
      "maintenance"
        expression => strcmp("$(inventory[maintenance])", "true");

      # One has_<service> class per inventory entry, name normalized
      # to lowercase/canonical form regardless of how it was cased in
      # the export.
      "has_$(with)"
        with => canonify(string_downcase("$(inventory[services][$(service_idx)][name])"));

  methods:
      # Data-supplied only_if expressions are parenthesized before
      # being combined with our own clauses: "." binds tighter than
      # "|", so an un-parenthesized "a|b" from the data would silently
      # attach only to the "b" side of "!maintenance.a|b".
      "svc_nginx"
        usebundle => svc_nginx,
        if        => "has_nginx.!maintenance.($(effective_only_if_nginx))";

      "svc_postgresql"
        usebundle => svc_postgresql,
        if        => "has_postgresql.!maintenance.($(effective_only_if_postgresql))";

      "svc_node_exporter"
        usebundle => svc_node_exporter,
        if        => "has_node_exporter.!maintenance.($(effective_only_if_node_exporter))";

      "svc_log_shipper"
        usebundle => svc_log_shipper,
        if        => "has_log_shipper.!maintenance.($(effective_only_if_log_shipper))";

      "svc_backup_agent"
        usebundle => svc_backup_agent,
        if        => "has_backup_agent.!maintenance.($(effective_only_if_backup_agent))";

      "svc_redis"
        usebundle => svc_redis,
        if        => "has_redis.!maintenance.($(effective_only_if_redis))";
}

#####################################################################

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

I verified it with `cf-promises -cf` and by running `cf-agent -K -f ./policy.cf` (mode 600, required by cf-agent) against the sample data — it correctly configured `nginx`, `node_exporter`, and `log_shipper` (weekday `only_if` true today) while skipping `backup_agent` (postgresql absent, so its `only_if` is false). I also confirmed `NGINX`/`PostgreSQL`/`rEdIs` casings all still match, and `maintenance: true` suppresses every bundle. Both `policy.cf` and `inventory.json` are in the working directory.