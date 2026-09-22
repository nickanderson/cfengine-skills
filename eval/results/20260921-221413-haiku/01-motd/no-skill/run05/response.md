I've created a complete CFEngine policy to manage the message of the day with 3 independent configurable variables. Here's the policy:

## motd.cf

```cfengine3
bundle agent motd {
  meta:
    "description" => "Manage system message of the day (motd)";
    "version" => "1.0";

  vars:
    "motd_file" string => "/etc/motd",
      policy => "free";

    "motd_content" string => "Welcome to the system",
      policy => "free";

    "motd_enabled" string => "true",
      policy => "free";

  classes:
    "motd_managing" expression => strcmp(motd.motd_enabled, "true");

  files:
    motd_managing::
      "$(motd.motd_file)"
        create => "true",
        edit_line => update_motd_content("$(motd.motd_content)"),
        perms => m(644),
        comment => "Ensure motd file exists with correct content";

  reports:
    motd_managing::
      "MOTD management enabled"
        report_to_file => "/var/log/cfengine_motd.log";
      "Setting MOTD file: $(motd.motd_file)"
        report_to_file => "/var/log/cfengine_motd.log";

    !motd_managing::
      "MOTD management is disabled"
        report_to_file => "/var/log/cfengine_motd.log";
}

bundle edit_line update_motd_content(content) {
  delete_lines:
    ".*";

  insert_lines:
    "$(content)";
}
```

## def.json (Augments Configuration)

```json
{
  "vars": {
    "motd": {
      "motd_file": "/etc/motd",
      "motd_content": "Welcome to the system\nManaged by CFEngine\nPlease login responsibly",
      "motd_enabled": "true"
    }
  }
}
```

## The 3 Configurable Variables

1. **motd_file** — Path to the motd file (default: `/etc/motd`)
2. **motd_content** — Message content, supports multi-line strings
3. **motd_enabled** — Boolean toggle to enable/disable management (default: `true`)

The policy uses `policy => "free"` on variable declarations, allowing augments in `def.json` to override them. When enabled, it creates/updates the motd file with the specified content and 644 permissions. All activities are logged to `/var/log/cfengine_motd.log`.