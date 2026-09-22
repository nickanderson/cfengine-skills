Policy validated with `cf-promises --full-check` and confirmed end-to-end: rendered content and augment overrides work correctly (I redirected the target file to a scratch path for the dry run since I don't have root to write `/etc/motd` here).

## `promises.cf`

```cfengine3
#######################################################
#
# Manage /etc/motd (message of the day).
#
# Three independent, augments-tunable variables control the content:
#   motd_organization    -- organization name shown in the banner
#   motd_support_contact -- contact info shown in the banner
#   motd_message         -- free-form notice/warning text
#
# Override any of them via def.json, e.g.:
#   {
#     "vars": {
#       "motd_organization": "Globex",
#       "motd_support_contact": "admin@example.com",
#       "motd_message": "Scheduled maintenance Friday 22:00 UTC."
#     }
#   }
#
#######################################################

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
                          "Example Corp"),
        comment => "Organization name displayed in the message of the day";

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                          "$(def.motd_support_contact)",
                          "support@example.com"),
        comment => "Support contact displayed in the message of the day";

      "message"
        string => ifelse(isvariable("def.motd_message"),
                          "$(def.motd_message)",
                          "Authorized users only. All activity may be monitored and reported."),
        comment => "Free-form notice displayed in the message of the day";

      "_template"
        string => "Welcome to {{{organization}}}$(const.n)$(const.n){{{message}}}$(const.n)$(const.n)Support: {{{support_contact}}}$(const.n)",
        comment => "Mustache template combining the three tunables into motd content";

      "_template_data"
        data => parsejson('{
          "organization": "$(motd.organization)",
          "support_contact": "$(motd.support_contact)",
          "message": "$(motd.message)"
        }'),
        comment => "Data container feeding the mustache template";

  files:
    linux::
      "/etc/motd"
        create => "true",
        perms => mode644,
        edit_template_string => "$(motd._template)",
        template_method => "inline_mustache",
        template_data => @(motd._template_data);
}

body perms mode644
{
      mode => "644";
      rxdirs => "false";
}
```

## `def.json` (example augments override)

```json
{
  "vars": {
    "motd_organization": "Globex",
    "motd_support_contact": "admin@example.com",
    "motd_message": "Scheduled maintenance Friday 22:00 UTC. Save your work."
  }
}
```

Notes on the design:
- The three tunables (`motd_organization`, `motd_support_contact`, `motd_message`) are independent — each falls back to its own default via the `isvariable()`/`ifelse()` pattern, so any subset can be overridden in `def.json` without affecting the others.
- Content is assembled with an inline mustache template (`{{{...}}}` triple-stash avoids HTML-escaping, which matters for a plain-text banner containing things like `&`).
- `/etc/motd` is gated on the `linux` hard class since that path is Linux-specific.
- Both files were placed in the current directory; `promises.cf` is mode 600 as required for CFEngine policy files.