Perfect! The policy validates successfully. Here's the complete CFEngine policy to manage the message of the day:

## Policy File: motd.cf

```cfengine3
body common control
{
  bundlesequence => { "motd" };
}

bundle agent motd
{
  vars:
      # Tunable via augments -- policy reads from def, falls back to default
      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                         "$(def.motd_organization)",
                         "Example Organization");

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                         "$(def.motd_support_contact)",
                         "support@example.com");

      "environment_label"
        string => ifelse(isvariable("def.motd_environment_label"),
                         "$(def.motd_environment_label)",
                         "production");

      # Construct the motd content using the configurable variables
      "content"
        string => "$(const.n)========================================================================$(const.n)Welcome to $(organization)$(const.n)Environment: $(environment_label)$(const.n)For support, contact: $(support_contact)$(const.n)========================================================================$(const.n)$(const.n)";

  files:
      "/etc/motd"
        create => "true",
        edit_line => motd_content("motd.content"),
        perms => m("0644");

  reports:
      "$(sys.date) [INFO] MOTD policy executed"
        meta => { "test_pass_marker" };
}

body perms m(mode)
{
  mode => "$(mode)";
}

bundle edit_line motd_content(content_var)
{
  delete_lines:
      ".*";

  insert_lines:
      "$($(content_var))";
}
```

## Augments File: def.json

```json
{
  "vars": {
    "motd_organization": "Acme Corporation",
    "motd_support_contact": "admin@example.com",
    "motd_environment_label": "production"
  }
}
```

## Overview

The policy provides **3 independent configurable variables** via augments:

1. **`motd_organization`** — Organization name displayed in the motd (default: "Example Organization")
2. **`motd_support_contact`** — Support contact information (default: "support@example.com")
3. **`motd_environment_label`** — Environment identifier (default: "production")

Each variable uses the **augments tunables pattern** with `isvariable()` and `ifelse()` to check if the variable is defined in `def.json`, falling back to a policy-defined default if not set. The policy generates formatted motd content dynamically and manages `/etc/motd` with appropriate file permissions.