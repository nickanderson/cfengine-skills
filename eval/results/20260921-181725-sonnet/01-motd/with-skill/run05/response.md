The policy manages `/etc/motd`, sourced from three independent values — `motd_organization`, `motd_support_contact`, and `motd_notice` — each tunable via `def.json` augments with sensible built-in defaults (per the augments tunables pattern in the skill reference). Verified with `cf-promises --full-check` and a dry-run `cf-agent` against a scratch target path, confirming both the augments-override and default-fallback paths render correctly.

**`motd.cf`**
```cfengine3
#######################################################
#
# Manage /etc/motd (message of the day).
#
# Three independent values used to build the motd content are
# tunable via augments (def.json), each falling back to a
# sensible default when not overridden:
#
#   motd_organization     -- organization name shown in the banner
#   motd_support_contact  -- support contact shown in the banner
#   motd_notice           -- notice/legal text shown in the banner
#
#######################################################

body common control
{
      bundlesequence => { "main" };
}

#######################################################

bundle agent main
{
  methods:
      "motd";
}

#######################################################

bundle agent motd
# @brief Manage the content of /etc/motd
{
  vars:
      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                          "$(def.motd_organization)",
                          "Example Corp"),
        comment => "Organization name shown in the motd. Tunable via augments as motd_organization.";

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                          "$(def.motd_support_contact)",
                          "support@example.com"),
        comment => "Support contact shown in the motd. Tunable via augments as motd_support_contact.";

      "notice"
        string => ifelse(isvariable("def.motd_notice"),
                          "$(def.motd_notice)",
                          "This system is for authorized use only. All activity may be monitored and reported."),
        comment => "Notice/legal text shown in the motd. Tunable via augments as motd_notice.";

      "content"
        string => "$(organization)$(const.n)$(const.n)$(notice)$(const.n)$(const.n)Support: $(support_contact)$(const.n)",
        comment => "Assembled motd content built from the three tunable variables above.";

  files:
      "/etc/motd"
        create => "true",
        content => "$(content)",
        perms => motd_mode("644");
}

#######################################################

body perms motd_mode(mode)
{
      mode   => "$(mode)";
      owners => { "root" };
      rxdirs => "false";
}
```

**`def.json`**
```json
{
  "vars": {
    "motd_organization": "Example Corp",
    "motd_support_contact": "support@example.com",
    "motd_notice": "This system is for authorized use only. All activity may be monitored and reported."
  }
}
```

To customize for a real deployment, edit the values in `def.json` (place it adjacent to your policy entry point, e.g. `promises.cf`) — no changes to `motd.cf` are needed.