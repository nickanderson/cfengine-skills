Everything validates. Summary of what was written to the working directory:

- **`motd.cf`** — `bundle agent motd` with three augments-configurable variables (`organization`, `support_contact`, `message`), each falling back to a sensible default via `isvariable()`/`ifelse()` if not set in augments. Renders `/etc/motd` via an inline Mustache template.
- **`promises.cf`** — minimal policy entry point (`body common control`) that runs the `motd` bundle.
- **`def.json`** — example augments file overriding all three variables.

Tested with `cf-promises -cf` (syntax check) and a standalone `cf-agent -KIf` run against a scratch output path, confirming the augments values (`Northern.tech` / `admin@example.com` / custom message) correctly override the defaults in the rendered output.

```cfengine3
bundle agent motd
# @brief Manage the contents of /etc/motd
{
  vars:
      # Organization name displayed in the banner.
      # Configurable via augments: def.json "vars" -> "motd_organization"
      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                          "$(def.motd_organization)",
                          "Example Corp"),
        comment => "Organization name shown in the message of the day";

      # Contact point for support/help requests.
      # Configurable via augments: def.json "vars" -> "motd_support_contact"
      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                          "$(def.motd_support_contact)",
                          "support@example.com"),
        comment => "Support contact shown in the message of the day";

      # Freeform notice/announcement text.
      # Configurable via augments: def.json "vars" -> "motd_message"
      "message"
        string => ifelse(isvariable("def.motd_message"),
                          "$(def.motd_message)",
                          "Authorized users only. All activity may be monitored and reported."),
        comment => "Notice text shown in the message of the day";

      "_data"
        data => mergedata('{
                              "organization": "$(motd.organization)",
                              "support_contact": "$(motd.support_contact)",
                              "message": "$(motd.message)",
                              "hostname": "$(sys.host)"
                            }');

  files:
      "/etc/motd"
        create          => "true",
        perms           => motd_perms,
        edit_template_string => "Welcome to {{hostname}}
Managed by: {{organization}}
Support: {{support_contact}}

{{message}}
",
        template_method => "inline_mustache",
        template_data   => @(_data),
        comment         => "Render /etc/motd from three augments-configurable variables";
}

body perms motd_perms
{
  mode   => "644";
  owners => { "root" };
  groups => { "root" };
  rxdirs => "false";
}
```

```cfengine3
body common control
{
      bundlesequence => { "motd" };
      inputs         => { "motd.cf" };
}
```

```json
{
  "variables": {
    "motd_organization": {
      "value": "Northern.tech",
      "comment": "Organization name shown in /etc/motd",
      "tags": ["motd"]
    },
    "motd_support_contact": {
      "value": "admin@example.com",
      "comment": "Support contact shown in /etc/motd",
      "tags": ["motd"]
    },
    "motd_message": {
      "value": "This system is managed by CFEngine. Unauthorized access is prohibited.",
      "comment": "Notice text shown in /etc/motd",
      "tags": ["motd"]
    }
  }
}
```