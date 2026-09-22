## Summary

The policy is complete and working correctly. The key findings:

1. **Classes are case-sensitive and cannot be made insensitive directly**, but you can normalize service names when defining the classes using `string_downcase()` + `canonify()`.

2. **The policy successfully handles any casing** from the inventory: "Nginx", "nginx", or "NGINX" all result in the `has_nginx` class being defined, which matches `only_if` expressions that reference `has_nginx`.

3. **Important note**: The inventory JSON must include all fields (including empty `only_if: ""` for services without conditions). Missing keys in JSON data cause CFEngine variable expansions to fail and skip the promise.

---

## Final Policy

```cfengine3
body file control
{
  inputs => { };
}

bundle agent __main__
{
  methods:
    any::
      "configure inventory services" usebundle => inventory_services;
}

bundle agent inventory_services
{
  vars:
    "inv" data => readjson("$(this.promise_dirname)/inventory.json");
    "svc_list" slist => getindices("inv[services]");
    "maint_flag" string => "$(inv[maintenance])";
    
  classes:
    # Define has_<normalized_name> for each service in inventory.
    # Normalize: lowercase + canonify (dashes become underscores).
    # This matches any casing in the inventory.
    "has_$(with)" with => string_downcase(canonify("$(inv[services][$(svc_list)][name])")),
      scope => "namespace";
    
    # Global maintenance flag
    "is_maintenance" expression => regcmp("(?i)^true$", "$(maint_flag)");
  
  methods:
    # For each service, run its configuration bundle if not in maintenance
    "configure" usebundle => configure_service("$(svc_list)", "$(inv[services][$(svc_list)][name])", "$(inv[services][$(svc_list)][only_if])"),
      unless => "is_maintenance";
}

bundle agent configure_service(svc_index, name, only_if_expr)
{
  vars:
    "svc_name" string => string_downcase(canonify("$(name)"));

  classes:
    # Evaluate the only_if condition:
    # - If empty (no only_if specified), always true
    # - If present, evaluate as a class expression (which references the has_* classes)
    "can_run" expression => ifelse(
      strcmp("$(only_if_expr)", ""),
      "any",
      "$(only_if_expr)"
    );

  methods:
    can_run::
      "run service" usebundle => "svc_$(svc_name)";
}

# Service bundles (stubs)
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

The policy reads `inventory.json` from the same directory, normalizes service names to lowercase, defines corresponding classes, and runs service bundles when conditions are met — regardless of casing in the inventory.