Complete policy:

```cfengine3
bundle agent main
{
  methods:
    "any" usebundle => configure_services();
}

bundle agent configure_services
{
  vars:
    "inventory_file" string => "$(this.promise_dirname)/inventory.json";
    "inventory" data => readjson($(inventory_file));
    "services" data => "$(inventory[services])";
    "indices" slist => getindices("services");

    # Normalize service names: lowercase + replace hyphens with underscores
    "name_lower[$(indices)]" string => tolower("$(services[$(indices)][name])");
    "name[$(indices)]" string => regex_replace("$(name_lower[$(indices)])", "-", "_", "g");

    # Extract only_if condition if present
    "only_if[$(indices)]" string => "$(services[$(indices)][only_if])",
      if => isvariable("services[$(indices)][only_if]");
    "only_if[$(indices)]" string => "",
      if => "!isvariable(\"services[$(indices)][only_if]\")";

  classes:
    # Define has_<service> classes with normalized names
    "has_$(name[$(indices)])" expression => "any";

    # Define maintenance class if inventory says so
    "maintenance"
      expression => "$(inventory[maintenance])",
      if => isvariable("inventory[maintenance]");

  methods:
    # Configure each service if not in maintenance
    "any" usebundle => configure_service("$(name[$(indices)])", "$(only_if[$(indices)])"),
      if => "has_$(name[$(indices)]).!maintenance";
}

bundle agent configure_service(service_name, only_if_expr)
{
  classes:
    # Evaluate the only_if condition if present
    "only_if_true"
      expression => evaluateclass("$(only_if_expr)"),
      if => strlen("$(only_if_expr)") > 0;

    # If no only_if expression, condition is always true
    "only_if_true"
      expression => "any",
      if => strlen("$(only_if_expr)") == 0;

  methods:
    "any" usebundle => "svc_$(service_name)",
      if => "only_if_true";
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

**How it works:**

1. **Reads inventory** from `$(this.promise_dirname)/inventory.json`
2. **Normalizes service names** by converting to lowercase and replacing hyphens with underscores (e.g., "Node-Exporter" → "node_exporter")
3. **Defines `has_<service>` classes** for each service, so regardless of how the inventory spells "Nginx", "nginx", or "NGINX", the class `has_nginx` is always defined
4. **Evaluates `only_if` expressions** using `evaluateclass()`, which by then can reference the normalized class names
5. **Skips service configuration** if the host is in maintenance mode or the `only_if` condition is false
6. **Runs the appropriate service bundle** (e.g., `svc_nginx`, `svc_postgresql`) only when all conditions are met

The policy is ready to run with: `cf-agent -K -f ./policy.cf`