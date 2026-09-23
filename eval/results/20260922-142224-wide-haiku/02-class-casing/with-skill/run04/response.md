## Answer

**No, CFEngine class expressions cannot be made case-insensitive** — there is no built-in flag or syntax to enable case-insensitive matching. Classes are strictly case-sensitive by design: `role_batch` and `role_Batch` are different classes.

**The solution:** Normalize service names to lowercase when you *define* the classes. Use `string_downcase()` and `canonify()` on the inventory data as it becomes a class. This is the pattern CFEngine recommends for classes derived from external data.

In this policy:
- Service names from inventory (e.g., `"Nginx"`, `"NGINX"`, `"nginx"`) are normalized using `string_downcase()` and `canonify()` when defining the `has_<service>` classes.
- All `only_if` expressions then reference these normalized class names (e.g., `has_nginx`) and work correctly regardless of the original casing in inventory.
- Services run only when their `has_<name>` class is defined, their `only_if` (if present) is true, and the host is not in maintenance.

## Complete Policy

```cfengine3
bundle agent main
{
  vars:
    "inventory" data => readjson("$(this.promise_dirname)/inventory.json");
    "svc_idx" slist => getindices("inventory[services]");

  classes:
    # Define has_<normalized_service_name> for each service in inventory.
    # The 'with' attribute normalizes the service name: lowercase + canonify
    # (replaces invalid chars like hyphens with underscores).
    # This ensures Nginx, NGINX, nginx all become has_nginx.
    "has_$(with)"
      with => canonify(string_downcase("$(inventory[services][$(svc_idx)][name])")),
      scope => "namespace";

    "maintenance"
      expression => "$(inventory[maintenance])",
      scope => "namespace";

  methods:
    # For each service in inventory, dispatch with condition checking.
    !maintenance::
      "dispatch_service_$(svc_idx)"
        usebundle => dispatch_service("$(svc_idx)");
}

bundle agent dispatch_service(idx)
{
  vars:
    # Normalize the service name for class and bundle references
    "svc_name" string => canonify(string_downcase("$(main.inventory[services][$(idx)][name])"));
    "svc_bundle" string => "svc_$(svc_name)";

    # Read only_if if present; default to "any" (always true) if absent.
    # This ensures the class expression is always valid.
    "only_if" string => ifelse(
      isvariable("main.inventory[services][$(idx)][only_if]"),
      "$(main.inventory[services][$(idx)][only_if])",
      "any"
    );

  methods:
    # Run the service bundle if its has_<name> class is defined
    # AND its only_if condition (if present) is true.
    # The parentheses around only_if are needed in case it contains OR (|).
    "execute"
      usebundle => $(svc_bundle),
      if => "has_$(svc_name).($(only_if))";
}

# Service bundle stubs
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