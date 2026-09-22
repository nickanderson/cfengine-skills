Perfect! I've created a CFEngine policy to manage the message of the day with 3 independent configurable variables. Here's what was built:

## Policy Overview

The solution consists of:

1. **motd.cf** — Agent bundle that manages `/etc/motd` with 3 configurable variables
2. **def.json** — Augments file defining the variables that can be overridden

## How It Works

The policy follows the **augments tunables pattern**:
- Each variable uses `ifelse(isvariable(...), ...)` to check if the augment is defined
- If defined in `def.json`, it uses that value; otherwise, it falls back to a built-in default
- The 3 variables are:
  - **`motd_organization`** — Organization name displayed in the MOTD
  - **`motd_support_contact`** — Support contact information
  - **`motd_custom_message`** — Custom message or security disclaimer

The policy writes these values to `/etc/motd` via the `insert_motd_content` edit_line bundle, which formats them into a readable message.

## Complete Policy Code

**motd.cf:**
```cfengine3
bundle agent motd
{
  vars:
      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                         "$(def.motd_organization)",
                         "Default Organization"),
        comment => "Organization name displayed in MOTD";

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                         "$(def.motd_support_contact)",
                         "support@example.com"),
        comment => "Support contact info displayed in MOTD";

      "custom_message"
        string => ifelse(isvariable("def.motd_custom_message"),
                         "$(def.motd_custom_message)",
                         "Please keep this system secure"),
        comment => "Custom message or disclaimer for MOTD";

  files:
      "/etc/motd"
        create => "true",
        edit_line => insert_motd_content,
        comment => "Manage message of the day";

  reports:
      "MOTD managed with organization: $(organization)";
      "Support contact configured as: $(support_contact)";
      "Custom message set to: $(custom_message)";
}

bundle edit_line insert_motd_content
{
  delete_lines:
      ".*";

  insert_lines:
      "Welcome to $(motd.organization)
Support: $(motd.support_contact)

$(motd.custom_message)";
}
```

**def.json:**
```json
{
  "vars": {
    "motd_organization": "Acme Corporation",
    "motd_support_contact": "ops-team@acme.com",
    "motd_custom_message": "Unauthorized access is prohibited. All activities are logged and monitored."
  }
}
```

Both files have been created in the working directory and validated. To use this policy, place both files in your CFEngine inputs directory and ensure `motd.cf` is included in your `promises.cf` or executed standalone.