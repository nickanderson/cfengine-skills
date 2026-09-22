## Summary

**Answer:** Class expressions in CFEngine are case-sensitive. You cannot make them case-insensitive directly. However, you can **normalize service names to lowercase when creating classes** — this ensures the `only_if` expressions (which reference lowercase class names like `has_nginx`) will match regardless of how the inventory specifies them (`Nginx`, `nginx`, or `NGINX`).

**How it works:**

1. **Normalization**: `canonify(tolower(...))` converts `"Nginx"` → `"nginx"` and `"Node-Exporter"` → `"node_exporter"`, then creates classes like `has_nginx` and `has_node_exporter`

2. **only_if evaluation**: The expressions from inventory are interpolated directly into class conditionals with parentheses for correct boolean precedence. For example, `"(has_nginx|has_postgresql)"` evaluates as a proper OR condition within the compound class expression.

3. **Maintenance override**: Services are only configured if the host is not in maintenance mode.

The policy reads `inventory.json` from the same directory and runs standalone with:
```bash
cf-agent -K -f ./policy.cf
```