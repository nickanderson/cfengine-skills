Perfect! I've created a CFEngine policy to manage the message of the day with three independent, configurable variables.

## Policy Summary

**motd.cf** provides a complete MOTD management solution with these 3 configurable variables:

1. **`motd_enabled`** — Controls whether MOTD management is active (`true` or `false`)
2. **`motd_content`** — The actual message of the day text to display
3. **`motd_file_path`** — The file path where the MOTD is stored (default: `/etc/motd`)

All variables are configurable via augments in `def.json` and have sensible defaults.

## Files Created

**motd.cf:**
```cf
bundle agent motd_management
{
  meta:
    "description"
      string => "Manage the message of the day (MOTD) with configurable content and settings";

  vars:
    "motd_enabled"
      string => getvar("def.motd_enabled", "true"),
      comment => "Enable or disable MOTD management (true/false)";

    "motd_content"
      string => getvar("def.motd_content", "Welcome to the system"),
      comment => "The content to display as the message of the day";

    "motd_file_path"
      string => getvar("def.motd_file_path", "/etc/motd"),
      comment => "Path to the MOTD file";

  classes:
    "enable_motd"
      expression => strcmp("$(motd_enabled)", "true"),
      comment => "Class to control whether MOTD management is active";

  files:
    enable_motd::
      "$(motd_file_path)"
        create => "true",
        edit_line => edit_motd("$(motd_content)"),
        perms => mog("0644", "root", "root"),
        comment => "Create or update the message of the day file";

  reports:
    enable_motd::
      "MOTD management: Configured MOTD at $(motd_file_path)"
        comment => "Report when MOTD is managed";

    !enable_motd::
      "MOTD management: Disabled"
        comment => "Report when MOTD management is disabled";
}

bundle edit_line edit_motd(content)
{
  delete_lines:
    ".*"
      comment => "Remove all existing content from MOTD file";

  insert_lines:
    "$(content)"
      location => after("BOF"),
      comment => "Insert the configured MOTD content";
}
```

**def.json:**
```json
{
  "classes": {
    "motd_enabled": ["any"]
  },
  "vars": {
    "motd_enabled": "true",
    "motd_content": "===============================================\nWelcome to the System\n===============================================\n\nThis is a managed system. All activity is monitored.\nUnauthorized access is prohibited and will be\nprosecuted by law.\n\n===============================================",
    "motd_file_path": "/etc/motd"
  }
}
```

## Usage

To use this policy, include the bundle in your main policy file and call it:

```cf
body file control
{
  inputs => { "motd.cf" };
}

bundle agent main
{
  methods:
    "any" usebundle => motd_management;
}
```

Customize the MOTD by modifying the values in your augments `def.json` file. Set `motd_enabled` to `"false"` to disable MOTD management without removing the policy.