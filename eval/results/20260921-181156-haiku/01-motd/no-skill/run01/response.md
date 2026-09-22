Perfect! I've created a CFEngine MOTD management policy with 3 configurable variables. Here's what I've generated:

## Policy File: `motd.cf`

```cfengine3
bundle agent motd_management
{
  meta:
    "description" => "Manage the system message of the day (MOTD)";
    "version" => "1.0";

  vars:
    "motd_enabled" 
      string => "$(def.motd_enabled)",
      comment => "Enable or disable MOTD management";

    "motd_file"
      string => "$(def.motd_file)",
      comment => "Path to the MOTD file";

    "motd_text"
      string => "$(def.motd_text)",
      comment => "Content of the MOTD file";

  classes:
    "motd_manage"
      expression => strcmp("$(motd_enabled)", "true"),
      comment => "Class set when MOTD management is enabled";

  files:
    motd_manage::
      "$(motd_file)"
        create        => "true",
        edit_line     => insert_lines("$(motd_text)"),
        perms         => mog("0644", "root", "root"),
        action        => if_elapsed(0),
        comment       => "Ensure MOTD file exists with correct content and permissions";

  reports:
    DEBUG::
      "MOTD management enabled: $(motd_enabled)"
        ifvarclass => "motd_manage";
      "MOTD file path: $(motd_file)";
      "MOTD content preview: $(motd_text)";

    !motd_manage::
      "MOTD management is disabled"
        action => if_elapsed(0);
}
```

## Configuration File: `def.json`

```json
{
  "motd_enabled": "true",
  "motd_file": "/etc/motd",
  "motd_text": "Welcome to this system\n\nFor support, contact: admin@example.com\nLast updated: 2026-09-21\n"
}
```

## The 3 Independent Variables

1. **`motd_enabled`** – Controls whether MOTD management is active (true/false)
2. **`motd_file`** – Path to the MOTD file (default: `/etc/motd`)
3. **`motd_text`** – The actual message content to display

All three variables are read from `def.json` via augments and can be customized independently. To use this policy, include the `motd_management` bundle in your main policy file and ensure your `def.json` is present in CFEngine's data directory.