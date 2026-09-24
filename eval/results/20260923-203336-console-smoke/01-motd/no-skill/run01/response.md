## CFEngine MOTD Management Policy

I've created a complete CFEngine policy to manage the message of the day with three independent, configurable variables. Here's the policy:

### **motd.cf**

```cfengine3
bundle agent motd
{
  vars:
      "motd_file"
        string => ifelse(
          isvariable("def.motd_file"),
          "$(def.motd_file)",
          "/etc/motd"
        ),
        comment => "Path to MOTD file - configurable via def.motd_file";

      "motd_enabled"
        string => ifelse(
          isvariable("def.motd_enabled"),
          "$(def.motd_enabled)",
          "true"
        ),
        comment => "Enable/disable MOTD management - configurable via def.motd_enabled";

      "motd_content"
        string => ifelse(
          isvariable("def.motd_content"),
          "$(def.motd_content)",
          "Welcome to the system"
        ),
        comment => "MOTD message content - configurable via def.motd_content";

  files:
      "$(motd_file)"
        create => "true",
        edit_line => insert_motd_content("$(motd_content)"),
        ifvarclass => "$(motd_enabled)_enabled",
        comment => "Manage MOTD file with configurable content";

  reports:
    DEBUG::
      "MOTD Policy: motd_file = $(motd_file)";
      "MOTD Policy: motd_enabled = $(motd_enabled)";
      "MOTD Policy: motd_content = $(motd_content)";
}

bundle edit_line insert_motd_content(content)
{
  delete_lines:
      ".*";

  insert_lines:
      "$(content)";
}
```

### **def.json** (Sample Configuration)

```json
{
  "classes": {
    "true_enabled": [
      "any"
    ]
  },
  "vars": {
    "motd_enabled": "true",
    "motd_file": "/etc/motd",
    "motd_content": "Welcome to Production Server\n\nFor administrative issues, contact: admin@example.com\n\nUnauthorized access is prohibited."
  }
}
```

## Three Configurable Variables

1. **`motd_enabled`** (default: "true") — Controls whether MOTD management is active
2. **`motd_file`** (default: "/etc/motd") — Specifies the MOTD file location
3. **`motd_content`** (default: "Welcome to the system") — The message content to display

All three variables are read from augments via `def.motd_enabled`, `def.motd_file`, and `def.motd_content`. If not defined, sensible defaults are used. The policy only manages the MOTD file when `motd_enabled` is set to "true".