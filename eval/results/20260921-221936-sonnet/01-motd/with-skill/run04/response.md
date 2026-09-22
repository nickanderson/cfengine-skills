The policy is validated and confirmed to render correctly end-to-end (defaults, augments override, and mustache substitution all work). Here are the final files.

**`motd.cf`**
```cfengine3
bundle agent motd
# @brief Manage /etc/motd content
#
# Three variables control the rendered content and are each configurable
# via augments (def.json), falling back to sensible defaults when unset:
#   - def.motd_organization    (string) organization name shown in the banner
#   - def.motd_support_contact (string) support contact shown in the banner
#   - def.motd_banner_message  (string) warning/notice message shown in the banner
{
  vars:
      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                          "$(def.motd_organization)",
                          "Example Corp"),
        comment => "Organization name displayed in the message of the day. Configurable via augments as motd_organization.";

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                          "$(def.motd_support_contact)",
                          "support@example.com"),
        comment => "Support contact displayed in the message of the day. Configurable via augments as motd_support_contact.";

      "banner_message"
        string => ifelse(isvariable("def.motd_banner_message"),
                          "$(def.motd_banner_message)",
                          "Authorized users only. All activity may be monitored and reported."),
        comment => "Notice/warning message displayed in the message of the day. Configurable via augments as motd_banner_message.";

      "template_data"
        data => parsejson('{
          "organization": "$(organization)",
          "support_contact": "$(support_contact)",
          "banner_message": "$(banner_message)",
          "hostname": "$(sys.host)",
          "policy_last_updated": "$(sys.date)"
        }'),
        comment => "Data container passed to the mustache template below.";

      "template"
        string => "================================================================
 Welcome to {{hostname}}
 Managed by: {{organization}}

 {{banner_message}}

 Support: {{support_contact}}
 Last policy update: {{policy_last_updated}}
================================================================
",
        comment => "Mustache template rendered into /etc/motd.";

  files:
      "/etc/motd"
        create              => "true",
        perms               => motd_perms,
        edit_template_string => "$(motd.template)",
        template_method      => "inline_mustache",
        template_data        => @(motd.template_data);
}

body perms motd_perms
{
      mode   => "644";
      owners => { "root" };
      groups => { "root" };
      rxdirs => "false";
}
```

**`promises.cf`**
```cfengine3
body common control
{
      bundlesequence  => { "motd" };
      inputs          => { "motd.cf" };
}
```

**`def.json`** (example augments — adjust or remove as needed)
```json
{
  "vars": {
    "motd_organization": "Northern.tech",
    "motd_support_contact": "admin@example.com",
    "motd_banner_message": "This system is for authorized use only. All activity is logged and monitored."
  }
}
```

Notes:
- The three tunables are `motd_organization`, `motd_support_contact`, `motd_banner_message`, each read via the `isvariable`/`ifelse` augments pattern with a built-in default if `def.json` doesn't set them.
- Validated with `cf-promises -cf ./promises.cf` (clean) and a dry run (`cf-agent -KIn -f ./promises.cf`), plus a real render to a scratch path confirming augments values flow through correctly into the mustache-templated `/etc/motd`.
- `motd_perms` sets `0644 root:root` since motd must be world-readable (the files promise default of `0600` would hide the banner from other users).