This is a generic policy pattern, not tied to a specific incident or user preference, so nothing here warrants a memory entry — moving on to the final answer.

## Summary

Wrote a CFEngine policy that manages `/etc/motd` with three independent, augments-tunable variables: `organization`, `support_contact`, and `notice`. Each falls back to a default when not set in `def.json`. Validated with `cf-promises --full-check` and confirmed both the default values and the `def.json`-overridden values resolve correctly via `cf-agent --show-evaluated-vars`.

**motd.cf**
```cfengine3
bundle agent motd
# @brief Manage the system's message of the day (/etc/motd)
#
# Three independent variables control the rendered content. Each is
# tunable via augments (def.json) and falls back to a sane default
# when not overridden:
#   - def.motd_organization      Organization name shown in the banner
#   - def.motd_support_contact   Contact info for support/help
#   - def.motd_notice            Free-form notice/warning text
{
  vars:
      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                          "$(def.motd_organization)",
                          "Acme Corp"),
        comment => "Organization name displayed in the motd banner, tunable via augments";

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                          "$(def.motd_support_contact)",
                          "support@example.com"),
        comment => "Support contact displayed in the motd, tunable via augments";

      "notice"
        string => ifelse(isvariable("def.motd_notice"),
                          "$(def.motd_notice)",
                          "Unauthorized access to this system is prohibited."),
        comment => "Notice/warning text displayed in the motd, tunable via augments";

      "content"
        string => "Welcome to $(organization)
$(sys.host)

Support: $(support_contact)
$(notice)
";

  files:
      "/etc/motd"
        create        => "true",
        content       => "$(content)",
        perms         => motd_perms("644", "root");
}

body perms motd_perms(mode, owner)
{
      mode   => "$(mode)";
      owners => { "$(owner)" };
}
```

**promises.cf**
```cfengine3
body common control
{
      bundlesequence => { "motd" };
      inputs         => { "motd.cf" };
}
```

**def.json**
```json
{
  "vars": {
    "motd_organization": "Northern.tech",
    "motd_support_contact": "admin@example.com",
    "motd_notice": "This system is monitored. Unauthorized access is prohibited."
  }
}
```