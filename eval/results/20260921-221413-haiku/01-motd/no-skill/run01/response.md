Done! I've created a CFEngine MOTD management policy with 3 independent configurable variables:

## Policy Overview

**motd.cf** — The main policy bundle that:
- Checks if MOTD management is enabled via `motd_enabled`
- Manages the MOTD file at the path specified in `motd_file`
- Writes the message content from `motd_message`
- Creates timestamped backups before editing
- Sets proper permissions (0644, owned by root)

**def.json** — Augments file defining the 3 variables:
1. **`motd_enabled`** (boolean) — Controls whether the policy actively manages MOTD
2. **`motd_message`** (string) — The actual content displayed as the message of the day
3. **`motd_file`** (string) — The file path where MOTD is stored (default: `/etc/motd`)

These variables can be overridden per-host or per-group by modifying the values in `def.json` before deployment.

## Files

```cfengine
# motd.cf
bundle agent motd
{
  meta:
    "description" string => "Manage the message of the day (MOTD)";
    "version" string => "1.0";

  classes:
    "motd_enabled" expression => "${def.motd_enabled}";

  files:
    motd_enabled::
      "${def.motd_file}"
        create        => "true",
        edit_defaults => motd_empty_backup,
        edit_line     => motd_content,
        perms         => motd_perms;

  reports:
    motd_enabled::
      "MOTD policy: Managing MOTD at ${def.motd_file}";

    !motd_enabled::
      "MOTD policy: MOTD management is disabled";
}

bundle edit_line motd_content
{
  delete_lines:
    any::
      ".*";

  insert_lines:
    any::
      "${def.motd_message}";
}

body edit_defaults motd_empty_backup
{
  empty_file_before_editing => "true";
  backup => "timestamp";
  max_file_size => "100K";
}

body perms motd_perms
{
  mode  => "0644";
  owners => { "root" };
  groups => { "root" };
}
```

```json
# def.json
{
  "variables": {
    "motd_enabled": {
      "value": true,
      "comment": "Enable or disable MOTD management"
    },
    "motd_message": {
      "value": "Welcome to the system!\nPlease use responsibly.\n",
      "comment": "Content to be displayed in the MOTD file"
    },
    "motd_file": {
      "value": "/etc/motd",
      "comment": "Path to the MOTD file"
    }
  }
}
```