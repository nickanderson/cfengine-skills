I've created a complete CFEngine policy for managing the message of the day. Here's what I've provided:

## Policy Files Created

**motd.cf** - Main policy with 3 independent configurable variables:
1. **enable** - Control whether MOTD management is active (default: "true")
2. **motd_file** - Path to the MOTD file (default: "/etc/motd")
3. **motd_content** - The content to write to MOTD (default: welcome message)

**def.json** - Augments file for configuring the variables

## Complete Policy Code

**motd.cf:**
```cfengine3
bundle common motd_settings
{
  vars:
    any::
      "enable"
        string => "true",
        comment => "Enable or disable MOTD management",
        handle => "motd_enable",
        meta => { "motd_config" };

      "motd_file"
        string => "/etc/motd",
        comment => "Path to the message of the day file",
        handle => "motd_file_path",
        meta => { "motd_config" };

      "motd_content"
        string => "Welcome to $(sys.hostname)

This system is for authorized use only.
Unauthorized access is prohibited.
",
        comment => "Content to be written to MOTD file",
        handle => "motd_content_var",
        meta => { "motd_config" };
}

bundle agent motd_policy
{
  meta:
    "description" => "Manage the system message of the day";
    "version" => "1.0";

  classes:
    "motd_management_enabled"
      expression => strcmp("$(motd_settings.enable)", "true"),
      comment => "Enable MOTD management only if explicitly enabled",
      handle => "motd_enabled_class";

  files:
    motd_management_enabled::
      "$(motd_settings.motd_file)"
        create => "true",
        content => "$(motd_settings.motd_content)",
        perms => mog("644", "root", "root"),
        comment => "Ensure MOTD file exists with correct content and permissions",
        handle => "motd_file_management";

  reports:
    motd_management_enabled::
      "MOTD Management: Updating $(motd_settings.motd_file) on $(sys.hostname)";

    !motd_management_enabled::
      "MOTD Management: Disabled on $(sys.hostname)";
}

body common control
{
  version => "1.0";
  inputs => { "$(sys.libdir)/stdlib.cf" };
  bundles => { "motd_policy" };
  commentary => "CFEngine policy for managing the system message of the day with
                 configurable variables via augments (def.json)";
}
```

**def.json (augments):**
```json
{
  "motd_settings": {
    "enable": "true",
    "motd_file": "/etc/motd",
    "motd_content": "Welcome to $(sys.hostname)\n\nThis is a production system.\nUnauthorized access is strictly prohibited.\n\nFor support, contact: admin@example.com\n"
  }
}
```

## Key Features

- **Three Independent Variables**: Easily control whether MOTD is managed, where it's located, and what content it contains
- **Augments Support**: All variables can be overridden via def.json without modifying the policy
- **Class-based Control**: Uses conditional classes so MOTD management is only active when enabled
- **Proper File Permissions**: Sets MOTD to 644 owned by root
- **Reporting**: Generates clear reports on policy actions
- **Metadata Tags**: Variables are tagged with "motd_config" for easy identification