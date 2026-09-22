I've created a CFEngine policy for managing the message of the day with 3 independent configurable variables.

## Policy Overview

**File: `motd.cf`** — The main policy bundle that manages MOTD content using three configurable variables:

1. **`motd_enabled`** — Controls whether MOTD management is active (true/false)
2. **`motd_file_path`** — The path to the MOTD file (default: `/etc/motd`)
3. **`motd_content`** — The actual message content to display

The policy:
- Reads all three variables from `def.json` augments
- Only manages the MOTD file when `motd_enabled` is "true"
- Replaces the entire file with the configured content
- Sets permissions to 644 with root ownership
- Reports the MOTD file location or disabled status

**File: `def.json`** — Sample augments file showing how to configure the variables for your environment.

---

## Complete Policy Code

**motd.cf:**
```cfengine3
bundle agent manage_motd
{
  vars:
    "motd_enabled"
      string => "$(def.motd_enabled)",
      comment => "Enable or disable MOTD management";

    "motd_file_path"
      string => "$(def.motd_file_path)",
      comment => "Path to the MOTD file";

    "motd_content"
      string => "$(def.motd_content)",
      comment => "Content of the message of the day";

  classes:
    "motd_enabled_class"
      expression => strcmp("$(motd_enabled)", "true"),
      comment => "Define class if MOTD management is enabled";

  files:
    motd_enabled_class::
      "$(motd_file_path)"
        create        => "true",
        edit_defaults => empty_defaults,
        edit_line     => insert_motd_content("$(motd_content)"),
        perms         => mog("644", "root", "root"),
        comment       => "Manage the message of the day file";

  reports:
    motd_enabled_class::
      "MOTD managed at: $(motd_file_path)";

    !motd_enabled_class::
      "MOTD management is disabled";
}

bundle edit_line insert_motd_content(content)
{
  insert_lines:
    "$(content)";
}

body edit_defaults empty_defaults
{
  empty_file_before_editing => "true";
  edit_backup               => "false";
}

body perms mog(mode, owner, group)
{
  mode   => "$(mode)";
  owners => { "$(owner)" };
  groups => { "$(group)" };
}
```

**def.json:**
```json
{
  "vars": {
    "motd_enabled": "true",
    "motd_file_path": "/etc/motd",
    "motd_content": "Welcome to the system\n\nThis is a managed server. Unauthorized access is prohibited.\nFor support, contact: admin@example.com\n"
  }
}
```

To use this policy, include it in your main `promises.cf` and ensure `manage_motd` is called in an appropriate bundle. Customize the `def.json` values for your environment.