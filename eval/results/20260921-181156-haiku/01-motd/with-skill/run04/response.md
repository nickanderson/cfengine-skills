Perfect! The policy validates successfully. Here are the two files I've created:

## motd.cf
```cfengine3
body common control
{
  bundlesequence => { "motd" };
}

bundle agent motd
{
  vars:
      "enabled"
        string => ifelse(isvariable("def.motd_enabled"),
                         "$(def.motd_enabled)",
                         "true");

      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                         "$(def.motd_organization)",
                         "Example Organization");

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                         "$(def.motd_support_contact)",
                         "support@example.com");

      "content"
        string => "
====================================================
Welcome to $(organization)
====================================================

System: $(sys.hostname)
OS: $(sys.os)
Architecture: $(sys.arch)

For support, contact: $(support_contact)

====================================================
";

  classes:
      "motd_enabled" expression => strcmp("$(enabled)", "true");

  files:
      "/etc/motd"
        create => "true",
        perms => mog("0644", "root", "root"),
        edit_line => insert_motd_content,
        if => "motd_enabled",
        comment => "Manage system message of the day";

  reports:
      "MOTD management enabled for $(organization)"
        if => "motd_enabled";

      "MOTD management is disabled"
        if => "!motd_enabled";
}

body perms mog(mode, owner, group)
{
  mode => "$(mode)";
  owners => { "$(owner)" };
  groups => { "$(group)" };
}

bundle edit_line insert_motd_content
{
  delete_lines:
      ".*" comment => "Remove all existing content";

  insert_lines:
      "$(motd.content)" comment => "Insert new MOTD content";
}
```

## def.json
```json
{
  "vars": {
    "motd_enabled": "true",
    "motd_organization": "Example Organization",
    "motd_support_contact": "support@example.com"
  }
}
```

### Policy Features

**Three Independent Configurable Variables:**
1. **`motd_enabled`** – Controls whether MOTD management is active (default: "true")
2. **`motd_organization`** – Organization name displayed in the MOTD (default: "Example Organization")
3. **`motd_support_contact`** – Support contact information in the MOTD (default: "support@example.com")

**How it works:**
- Each variable uses the augments tunable pattern (`isvariable()` + `ifelse()`) to read from `def.json` with sensible defaults
- The policy creates/manages `/etc/motd` with formatted content including hostname, OS, and architecture
- MOTD management can be completely disabled by setting `motd_enabled` to "false"
- The policy uses an `edit_line` bundle to cleanly replace MOTD content
- File permissions are set to 0644 (root:root) for universal readability

Override any variable by modifying `def.json` before running the policy.