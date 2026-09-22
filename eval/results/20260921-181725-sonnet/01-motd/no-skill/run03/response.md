Both files are validated and working (confirmed via `cf-promises` syntax check and a live `cf-agent` run that correctly rendered content from the augmented values). Here's the final policy.

**promises.cf**
```cfengine3
#######################################################
#
# Manage /etc/motd (message of the day)
#
# Content is assembled from three independently
# configurable variables:
#   - def.motd_banner   top banner/greeting line
#   - def.motd_notice    security/legal notice line
#   - def.motd_contact   support contact line
#
# Each of these can be overridden via augments (def.json)
# using the fully qualified name "default:def.<name>".
# If no augment is supplied, a built-in default is used.
#
#######################################################

body common control
{
      bundlesequence => { "motd" };
}

bundle agent motd
{
  vars:
      "banner"
        string => ifelse(isvariable("def.motd_banner"),
                          "$(def.motd_banner)",
                          "Welcome to $(sys.host)"),
        comment => "Top banner line for /etc/motd. Override via augments as default:def.motd_banner.";

      "notice"
        string => ifelse(isvariable("def.motd_notice"),
                          "$(def.motd_notice)",
                          "This system is monitored. Unauthorized access is prohibited."),
        comment => "Security/legal notice line for /etc/motd. Override via augments as default:def.motd_notice.";

      "contact"
        string => ifelse(isvariable("def.motd_contact"),
                          "$(def.motd_contact)",
                          "For support, contact your local system administrator."),
        comment => "Support contact line for /etc/motd. Override via augments as default:def.motd_contact.";

      "content"
        string => "$(banner)$(const.n)$(const.n)$(notice)$(const.n)$(const.n)$(contact)$(const.n)",
        comment => "Full assembled MOTD content built from the three configurable variables above.";

  files:
      "/etc/motd"
        create        => "true",
        edit_line     => motd_set_content("$(content)"),
        edit_defaults => motd_empty_before_edit,
        perms         => motd_perms,
        comment       => "Render the message of the day from configurable variables.";
}

bundle edit_line motd_set_content(content)
{
  insert_lines:
      "$(content)"
        comment => "Insert the freshly assembled MOTD content.";
}

body edit_defaults motd_empty_before_edit
{
      empty_file_before_editing => "true";
}

body perms motd_perms
{
      mode   => "644";
      owners => { "root" };
      groups => { "root" };
      rxdirs => "false";
}
```

**def.json**
```json
{
  "variables": {
    "default:def.motd_banner": {
      "value": "Welcome to Example Corp - Authorized Access Only",
      "comment": "Banner line shown at the top of /etc/motd"
    },
    "default:def.motd_notice": {
      "value": "This system is monitored. All activity may be logged and reviewed.",
      "comment": "Security/legal notice line shown in /etc/motd"
    },
    "default:def.motd_contact": {
      "value": "Questions? Contact support@example.com",
      "comment": "Support contact line shown in /etc/motd"
    }
  }
}
```

Notes on design:
- The three variables — `motd_banner`, `motd_notice`, `motd_contact` — are each independent and individually overridable via `def.json` augments (the standard CFEngine mechanism, auto-loaded from the same directory as `promises.cf`).
- Each uses `isvariable("def.<name>")` + `ifelse()` to fall back to a sensible built-in default if the augment isn't present, so the policy works even with no `def.json` at all.
- `/etc/motd` is emptied and rewritten each run (`empty_file_before_editing`) so changes to the augment values are reliably reflected, rather than stacking stale content.
- Tested locally with `cf-promises` (syntax) and `cf-agent` (functional dry-run and a real write to a scratch path), confirming the augmented values from `def.json` flow through correctly.