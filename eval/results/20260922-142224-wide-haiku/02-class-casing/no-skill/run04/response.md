## How the Policy Solves Case-Insensitivity

The policy uses **normalization at class definition time**:

1. **Normalize service names**: `tolower()` and `regex_replace()` convert all names to lowercase with underscores (e.g., `Nginx` → `nginx`, `Node-Exporter` → `node_exporter`)

2. **Define classes uniformly**: All variants create the same class: `has_nginx` (regardless of whether the inventory says `Nginx`, `nginx`, or `NGINX`)

3. **Build dynamic conditions**: For each service, construct the full condition by combining:
   - The service's own class: `has_<service>`
   - The `only_if` expression (if present): wrapped in parentheses for correct precedence
   - Negated maintenance flag: `!maintenance`

4. **Call bundles conditionally**: Use `ifvarclass` to expand the constructed condition string and call the appropriate bundle only when all conditions hold

This approach works because the `only_if` expressions use lowercase class names—once you normalize the inventory to lowercase, those expressions will find matching classes.

---

## Final Policy

```cfengine3
bundle agent main {
  vars:
    "inventory_file" string => "$(this.promise_dirname)/inventory.json";
    "inventory" data => readjson($(inventory_file));
    "is_maintenance_value" string => "$(inventory[maintenance])";
    "idx" slist => getindices("inventory[services]");
    
    # Normalize service names: lowercase and replace hyphens with underscores
    "svc[$(idx)]" string => regex_replace(tolower("$(inventory[services][$(idx)][name])"), "-", "_", "g");
    
    # Get only_if condition (default to empty string if not present)
    "only_if[$(idx)]" string => "$(inventory[services][$(idx)][only_if])",
      if => haskey("inventory[services][$(idx)]", "only_if");
    "only_if[$(idx)]" string => "",
      unless => haskey("inventory[services][$(idx)]", "only_if");
    
    # Build full condition string with parentheses around only_if for proper precedence
    "full_condition[$(idx)]" string => "has_$(svc[$(idx)]).($(only_if[$(idx)]))",
      if => not(strcmp("$(only_if[$(idx)])", ""));
    "full_condition[$(idx)]" string => "has_$(svc[$(idx)])",
      if => strcmp("$(only_if[$(idx)])", "");
      
  classes:
    # Define has_<service> classes with lowercase and underscore-normalized names
    # This ensures "Nginx", "nginx", and "NGINX" all create the same class "has_nginx"
    "has_$(svc[$(idx)])" expression => "any";
    
    # Define maintenance class based on inventory value
    "maintenance" expression => strcmp("$(is_maintenance_value)", "true");
    
  methods:
    # Call service bundle with the constructed condition
    "svc_$(svc[$(idx)])"
      usebundle => "svc_$(svc[$(idx)])"
      ifvarclass => "$(full_condition[$(idx)]).!maintenance";
}

# Service bundle definitions (stubs that report configuration)
bundle agent svc_nginx {
  reports:
    "CONFIGURED: svc_nginx";
}

bundle agent svc_postgresql {
  reports:
    "CONFIGURED: svc_postgresql";
}

bundle agent svc_node_exporter {
  reports:
    "CONFIGURED: svc_node_exporter";
}

bundle agent svc_log_shipper {
  reports:
    "CONFIGURED: svc_log_shipper";
}

bundle agent svc_backup_agent {
  reports:
    "CONFIGURED: svc_backup_agent";
}

bundle agent svc_redis {
  reports:
    "CONFIGURED: svc_redis";
}
```

The policy is ready to run with `cf-agent -K -f ./policy.cf` and will handle any combination of casing in the inventory.