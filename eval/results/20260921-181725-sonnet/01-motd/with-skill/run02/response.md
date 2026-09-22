The policy is written and validated (dry-run confirmed correct mustache rendering with augmented values). No memory-worthy new facts here — this is a self-contained scratch task with no user preferences, corrections, or project context to persist.

## Summary

Wrote a CFEngine module that manages `/etc/motd` with three augment-configurable tunables (`motd_organization`, `motd_notice`, `motd_support_contact`), each falling back to a default when unset in `def.json`. Content is rendered via an inline Mustache template that also includes non-configurable host facts (hostname, OS). Verified with `cf-promises --full-check` and a live `cf-agent -KIf` dry-run against a scratch output path — confirmed the augmented `def.json` values flow through correctly.

**`motd.cf`**
```cfengine3
bundle agent motd
# @brief Manage the system message of the day (/etc/motd)
#
# Three tunables control the content and are configurable via augments
# (def.json), falling back to sane defaults when not set:
#   - def.motd_organization    organization name displayed in the banner
#   - def.motd_notice          legal/security notice text
#   - def.motd_support_contact contact info for support/help
{
  vars:
      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                          "$(def.motd_organization)",
                          "Example Corp"),
        comment => "Organization name shown in the message of the day. Configurable via augments (def.json key: motd_organization)";

      "notice"
        string => ifelse(isvariable("def.motd_notice"),
                          "$(def.motd_notice)",
                          "Authorized users only. All activity may be monitored and reported."),
        comment => "Notice/warning text shown in the message of the day. Configurable via augments (def.json key: motd_notice)";

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                          "$(def.motd_support_contact)",
                          "support@example.com"),
        comment => "Support contact shown in the message of the day. Configurable via augments (def.json key: motd_support_contact)";

      "_content_template"
        string => "{{organization}}

{{notice}}

Host: {{hostname}} ({{os}})
Support: {{support_contact}}
",
        comment => "Mustache template for /etc/motd content";

      "_template_data"
        data => parsejson('{
          "organization": "$(organization)",
          "notice": "$(notice)",
          "support_contact": "$(support_contact)",
          "hostname": "$(sys.fqhost)",
          "os": "$(sys.flavor)"
        }'),
        comment => "Data container passed to the mustache template, built from the tunables plus host facts";

  files:
      "/etc/motd"
        create               => "true",
        perms                => mo("644"),
        edit_template_string => "$(motd._content_template)",
        template_method      => "inline_mustache",
        template_data        => @(motd._template_data);
}

body perms mo(mode)
{
      mode   => "$(mode)";
      owners => { "root" };
}
```

**`promises.cf`** (entry point, for standalone testing/deployment)
```cfengine3
body common control
{
      bundlesequence => { "motd" };
      inputs         => { "motd.cf" };
}
```

**`def.json`** (example augments overriding the three tunables)
```json
{
  "vars": {
    "motd_organization": "Northern.tech",
    "motd_notice": "Authorized users only. All activity may be monitored and reported.",
    "motd_support_contact": "admin@example.com"
  }
}
```

All three files are in the working directory (`motd.cf` and `promises.cf` at mode 600 per CFEngine's policy-file requirement, `def.json` at 644). To use this in an existing policy set, just copy `motd.cf` in, add `"motd.cf"` to your entry point's `inputs`, add `"motd"` to `bundlesequence` (or call it via `methods`), and override values in your real `def.json`.