Done! I've created a CFEngine MOTD management policy with 3 independent configurable variables:

## **The 3 Configurable Variables:**

1. **`motd_enabled`** — Boolean flag to enable/disable MOTD management (default: "true")
2. **`motd_path`** — File path where MOTD is stored (default: "/etc/motd")
3. **`motd_content`** — The actual message of the day text content
4. **`motd_perms`** — File permissions for the MOTD file (default: "0644")

All variables are defined in `def.json` (augments) and accessed via `${def.*}` in the policy.

## **Files Created:**

**motd.cf** — The main policy bundle:
```cfengine3
bundle agent manage_motd
{
  meta:
    "description" string => "Manage system message of the day";
    "version" string => "1.0";

  classes:
    "motd_enabled"
      expression => strcmp("${def.motd_enabled}", "true"),
      comment => "Check if MOTD management is enabled";

  files:
    motd_enabled::
      "${def.motd_path}"
        create => "true",
        content => "${def.motd_content}",
        perms => mog("${def.motd_perms}", "root", "root"),
        comment => "Manage message of the day file";

  reports:
    motd_enabled.DEBUG::
      "MOTD Management - Enabled: ${def.motd_enabled}";
      "MOTD Management - Path: ${def.motd_path}";
      "MOTD Management - Permissions: ${def.motd_perms}";
}
```

**def.json** — Augments configuration:
```json
{
  "classes": {
    "enterprise_enabled": [ "default:enabled" ]
  },
  "vars": {
    "motd_enabled": "true",
    "motd_path": "/etc/motd",
    "motd_content": "Welcome to the system!\n\nThis is a managed system monitored by CFEngine.\nUnauthorized access is prohibited.\n\nFor support, contact: admin@example.com\n",
    "motd_perms": "0644"
  }
}
```

**promises.cf** — Main policy entry point:
```cfengine3
body file control
{
  inputs => { "motd.cf" };
}

bundle agent main
{
  methods:
    "manage_motd" usebundle => manage_motd();
}
```

The policy will create/manage the MOTD file only when `motd_enabled` is "true", using all three variables to configure the behavior.