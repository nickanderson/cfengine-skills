Policy validated and confirmed working end-to-end (rendered output matched the augments-supplied values). Final files in the working directory: `motd.cf`, `promises.cf` (entry point for testing), and `def.json` (sample overrides).

**motd.cf**
```cfengine3
# Manages /etc/motd content.
#
# Three tunables, each overridable via augments (def.json):
#   def.motd_organization     -- organization/site name shown in the banner
#   def.motd_support_contact  -- contact info for support/helpdesk
#   def.motd_notice           -- free-form notice/legal text appended to the banner

bundle agent motd
{
  vars:
      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                          "$(def.motd_organization)",
                          "Example Corp"),
        comment => "Tunable via augments key motd_organization";

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                          "$(def.motd_support_contact)",
                          "support@example.com"),
        comment => "Tunable via augments key motd_support_contact";

      "notice"
        string => ifelse(isvariable("def.motd_notice"),
                          "$(def.motd_notice)",
                          "Unauthorized access to this system is prohibited."),
        comment => "Tunable via augments key motd_notice";

      "path"
        string => "/etc/motd";

      "content"
        string => "Welcome to $(motd.organization)
Managed by CFEngine -- for support, contact $(motd.support_contact)

$(motd.notice)
";

  files:
      "$(motd.path)"
        create        => "true",
        content       => "$(motd.content)",
        perms         => motd_perms("644", "root");
}

body perms motd_perms(mode, owner)
{
      mode   => "$(mode)";
      owners => { "$(owner)" };
      rxdirs => "false";
}
```

**promises.cf** (entry point, for standalone testing/inclusion)
```cfengine3
body common control
{
      bundlesequence => { "motd" };
      inputs         => { "motd.cf" };
}
```

**def.json** (sample overrides — adjust or remove keys to use policy defaults)
```json
{
  "vars": {
    "motd_organization": "Globex Corporation",
    "motd_support_contact": "admin@example.com",
    "motd_notice": "Unauthorized access to this system is prohibited and will be logged."
  }
}
```

Notes:
- The three independent tunables are `motd_organization`, `motd_support_contact`, and `motd_notice`. Each falls back to a sensible built-in default via `isvariable()` + `ifelse()` if not set in `def.json`, so the policy works unmodified even without augments.
- To wire this into an existing policy set, add `"motd.cf"` to your `inputs` and `"motd"` to your `bundlesequence` instead of using the standalone `promises.cf` shown here.
- Verified with `cf-promises -f ./promises.cf` (syntax OK) and a live `cf-agent -KIf` run against a scratch path, confirming augments values flow through to the rendered file content.