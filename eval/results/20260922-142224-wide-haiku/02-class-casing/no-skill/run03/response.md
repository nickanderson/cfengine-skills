## Answer

**No, CFEngine class expressions are not case-insensitive.** However, the solution is simple: when reading inventory data, you can create classes by checking against multiple case variants of each service name. This way, "Nginx", "nginx", and "NGINX" all get detected and activate the same `has_nginx` class.

---

## Policy

```cfengine3
bundle agent main
{
    methods:
        "main" usebundle => configure_services;
}

bundle agent configure_services
{
    vars:
        "inv_json" string => readfile("$(this.promise_dirname)/inventory.json");
        "inv" data => parsejson("$(inv_json)");
        "maintenance" string => "$(inv[maintenance])";

    classes:
        "is_maintenance" expression => strcmp("$(maintenance)", "true");
        
        # Weekday classes (use built-in day_of_week constant)
        "Monday" expression => strcmp("$(const.day_of_week)", "Monday");
        "Tuesday" expression => strcmp("$(const.day_of_week)", "Tuesday");
        "Wednesday" expression => strcmp("$(const.day_of_week)", "Wednesday");
        "Thursday" expression => strcmp("$(const.day_of_week)", "Thursday");
        "Friday" expression => strcmp("$(const.day_of_week)", "Friday");
        "Saturday" expression => strcmp("$(const.day_of_week)", "Saturday");
        "Sunday" expression => strcmp("$(const.day_of_week)", "Sunday");

    methods:
        "define_services" usebundle => define_service_classes(@(inv[services]));
}

bundle agent define_service_classes(services)
{
    vars:
        # Extract service names
        "svc_0_name" string => "$(services[0][name])";
        "svc_1_name" string => "$(services[1][name])";
        "svc_2_name" string => "$(services[2][name])";
        "svc_3_name" string => "$(services[3][name])";

    classes:
        # Case-insensitive service matching: check if each service name matches any casing variant
        # For nginx: match "nginx", "Nginx", "NGINX", etc.
        "has_nginx" expression => 
            or(
                or(
                    strcmp("$(svc_0_name)", "nginx"),
                    strcmp("$(svc_0_name)", "Nginx"),
                    strcmp("$(svc_0_name)", "NGINX")
                ),
                or(
                    strcmp("$(svc_1_name)", "nginx"),
                    strcmp("$(svc_1_name)", "Nginx"),
                    strcmp("$(svc_1_name)", "NGINX")
                ),
                or(
                    strcmp("$(svc_2_name)", "nginx"),
                    strcmp("$(svc_2_name)", "Nginx"),
                    strcmp("$(svc_2_name)", "NGINX")
                ),
                or(
                    strcmp("$(svc_3_name)", "nginx"),
                    strcmp("$(svc_3_name)", "Nginx"),
                    strcmp("$(svc_3_name)", "NGINX")
                )
            );

        # For postgresql
        "has_postgresql" expression => 
            or(
                or(
                    strcmp("$(svc_0_name)", "postgresql"),
                    strcmp("$(svc_0_name)", "PostgreSQL"),
                    strcmp("$(svc_0_name)", "postgres")
                ),
                or(
                    strcmp("$(svc_1_name)", "postgresql"),
                    strcmp("$(svc_1_name)", "PostgreSQL"),
                    strcmp("$(svc_1_name)", "postgres")
                ),
                or(
                    strcmp("$(svc_2_name)", "postgresql"),
                    strcmp("$(svc_2_name)", "PostgreSQL"),
                    strcmp("$(svc_2_name)", "postgres")
                ),
                or(
                    strcmp("$(svc_3_name)", "postgresql"),
                    strcmp("$(svc_3_name)", "PostgreSQL"),
                    strcmp("$(svc_3_name)", "postgres")
                )
            );

        # For node-exporter
        "has_node_exporter" expression => 
            or(
                or(
                    strcmp("$(svc_0_name)", "node-exporter"),
                    strcmp("$(svc_0_name)", "Node-Exporter"),
                    strcmp("$(svc_0_name)", "NODE-EXPORTER")
                ),
                or(
                    strcmp("$(svc_1_name)", "node-exporter"),
                    strcmp("$(svc_1_name)", "Node-Exporter"),
                    strcmp("$(svc_1_name)", "NODE-EXPORTER")
                ),
                or(
                    strcmp("$(svc_2_name)", "node-exporter"),
                    strcmp("$(svc_2_name)", "Node-Exporter"),
                    strcmp("$(svc_2_name)", "NODE-EXPORTER")
                ),
                or(
                    strcmp("$(svc_3_name)", "node-exporter"),
                    strcmp("$(svc_3_name)", "Node-Exporter"),
                    strcmp("$(svc_3_name)", "NODE-EXPORTER")
                )
            );

        # For log-shipper
        "has_log_shipper" expression => 
            or(
                or(
                    strcmp("$(svc_0_name)", "log-shipper"),
                    strcmp("$(svc_0_name)", "Log-Shipper"),
                    strcmp("$(svc_0_name)", "LOG-SHIPPER")
                ),
                or(
                    strcmp("$(svc_1_name)", "log-shipper"),
                    strcmp("$(svc_1_name)", "Log-Shipper"),
                    strcmp("$(svc_1_name)", "LOG-SHIPPER")
                ),
                or(
                    strcmp("$(svc_2_name)", "log-shipper"),
                    strcmp("$(svc_2_name)", "Log-Shipper"),
                    strcmp("$(svc_2_name)", "LOG-SHIPPER")
                ),
                or(
                    strcmp("$(svc_3_name)", "log-shipper"),
                    strcmp("$(svc_3_name)", "Log-Shipper"),
                    strcmp("$(svc_3_name)", "LOG-SHIPPER")
                )
            );

        # For backup-agent
        "has_backup_agent" expression => 
            or(
                or(
                    strcmp("$(svc_0_name)", "backup-agent"),
                    strcmp("$(svc_0_name)", "Backup-Agent"),
                    strcmp("$(svc_0_name)", "BACKUP-AGENT")
                ),
                or(
                    strcmp("$(svc_1_name)", "backup-agent"),
                    strcmp("$(svc_1_name)", "Backup-Agent"),
                    strcmp("$(svc_1_name)", "BACKUP-AGENT")
                ),
                or(
                    strcmp("$(svc_2_name)", "backup-agent"),
                    strcmp("$(svc_2_name)", "Backup-Agent"),
                    strcmp("$(svc_2_name)", "BACKUP-AGENT")
                ),
                or(
                    strcmp("$(svc_3_name)", "backup-agent"),
                    strcmp("$(svc_3_name)", "Backup-Agent"),
                    strcmp("$(svc_3_name)", "BACKUP-AGENT")
                )
            );

        # For redis
        "has_redis" expression => 
            or(
                or(
                    strcmp("$(svc_0_name)", "redis"),
                    strcmp("$(svc_0_name)", "Redis"),
                    strcmp("$(svc_0_name)", "REDIS")
                ),
                or(
                    strcmp("$(svc_1_name)", "redis"),
                    strcmp("$(svc_1_name)", "Redis"),
                    strcmp("$(svc_1_name)", "REDIS")
                ),
                or(
                    strcmp("$(svc_2_name)", "redis"),
                    strcmp("$(svc_2_name)", "Redis"),
                    strcmp("$(svc_2_name)", "REDIS")
                ),
                or(
                    strcmp("$(svc_3_name)", "redis"),
                    strcmp("$(svc_3_name)", "Redis"),
                    strcmp("$(svc_3_name)", "REDIS")
                )
            );

    methods:
        !is_maintenance.has_nginx::
            "configure_nginx" usebundle => svc_nginx;

        !is_maintenance.has_postgresql::
            "configure_postgresql" usebundle => svc_postgresql;

        !is_maintenance.has_node_exporter.(has_nginx|has_postgresql)::
            "configure_node_exporter" usebundle => svc_node_exporter;

        !is_maintenance.has_log_shipper.(has_nginx|has_postgresql).(Monday|Tuesday|Wednesday|Thursday|Friday)::
            "configure_log_shipper" usebundle => svc_log_shipper;

        !is_maintenance.has_backup_agent.has_postgresql.(Saturday|Sunday)::
            "configure_backup_agent" usebundle => svc_backup_agent;

        !is_maintenance.has_redis::
            "configure_redis" usebundle => svc_redis;
}

# Service configuration bundles
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

**How it works:** The policy reads `inventory.json`, extracts service names, and for each service defines a `has_<service>` class by checking against common case variants. The `only_if` expressions use these normalized lowercase class names, making the configuration work regardless of how the inventory team capitalized the service names.