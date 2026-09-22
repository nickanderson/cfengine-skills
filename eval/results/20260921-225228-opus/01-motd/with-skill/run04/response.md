Both the augments-override and the policy-default paths are verified working.

## Files written to `/tmp/cfeval-01-motd-with-skill.tQ1UXXkO/work`

**`motd.cf`** — the policy bundle:

```cfengine3
bundle agent motd
# @brief Manage the content of the message of the day (/etc/motd)
#
# Three independent, augments-tunable variables drive the rendered content:
#
#   def.motd_organization    - Organization name shown in the banner
#   def.motd_support_contact - Who to contact for help with this host
#   def.motd_access_policy   - Access/authorization statement
#
# Each falls back to a policy default when not defined by augments.
{
  vars:
      # --- Tunables (override via def.json) -------------------------------
      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                         "$(def.motd_organization)",
                         "Northern.tech"),
        comment => "Organization name rendered in the MOTD banner";

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                         "$(def.motd_support_contact)",
                         "support@example.com"),
        comment => "Contact address for assistance with this host";

      "access_policy"
        string => ifelse(isvariable("def.motd_access_policy"),
                         "$(def.motd_access_policy)",
                         "Authorized use only. All activity may be monitored and recorded."),
        comment => "Access/authorization statement rendered in the MOTD";

      # --- Where the MOTD lives ------------------------------------------
      "motd_file"
        string => ifelse(isvariable("def.motd_file"),
                         "$(def.motd_file)",
                         "/etc/motd"),
        comment => "Path to the message of the day file";

      # --- Template data --------------------------------------------------
      # Only the values the template needs, so datastate() is never used.
      "template_data"
        data => parsejson('{
                            "organization": "$(organization)",
                            "support_contact": "$(support_contact)",
                            "access_policy": "$(access_policy)",
                            "fqhost": "$(sys.fqhost)",
                            "os": "$(sys.flavor)"
                          }');

      "template"
        string => concat(
          "*****************************************************************$(const.n)",
          "  {{{organization}}} - {{{fqhost}}} ({{{os}}})$(const.n)",
          "*****************************************************************$(const.n)",
          "$(const.n)",
          "  {{{access_policy}}}$(const.n)",
          "$(const.n)",
          "  Need help? Contact {{{support_contact}}}$(const.n)",
          "$(const.n)",
          "*****************************************************************$(const.n)"),
        comment => "Inline mustache template for the MOTD body";

  files:
      "$(motd_file)"
        create => "true",
        perms => mog("0644", "root", "root"),
        edit_template_string => "$(template)",
        template_method => "inline_mustache",
        template_data => @(template_data),
        classes => results("bundle", "motd_content"),
        comment => "Render the message of the day from the tunable values";

  reports:
    motd_content_repaired::
      "$(this.bundle): Updated $(motd_file) for '$(organization)'";

    DEBUG|DEBUG_motd::
      "$(this.bundle): organization    = '$(organization)'";
      "$(this.bundle): support_contact = '$(support_contact)'";
      "$(this.bundle): access_policy   = '$(access_policy)'";
}
```

**`def.json`** — augments, adjacent to the policy entry point:

```json
{
  "variables": {
    "motd_organization": {
      "value": "Northern.tech",
      "comment": "Organization name rendered in the MOTD banner",
      "tags": [ "motd" ]
    },
    "motd_support_contact": {
      "value": "admin@example.com",
      "comment": "Contact address for assistance with this host",
      "tags": [ "motd" ]
    },
    "motd_access_policy": {
      "value": "Authorized use only. All activity may be monitored and recorded.",
      "comment": "Access/authorization statement rendered in the MOTD",
      "tags": [ "motd" ]
    }
  }
}
```

**`promises.cf`** — standalone entry point (drop `motd.cf` into `services/` and add the bundle to your `bundlesequence` instead, if integrating into masterfiles):

```cfengine3
body common control
# @brief Standalone entry point for the motd policy
{
      bundlesequence => { "motd" };

      inputs => {
                  "$(sys.libdir)/stdlib.cf",
                  "motd.cf",
                };
}
```

## Notes

- **The three tunables** are `motd_organization`, `motd_support_contact`, and `motd_access_policy`. Each is independently overridable — setting one in `def.json` does not require setting the others; anything left out falls back to its policy default via the `isvariable()` + `ifelse()` instrumentation. `motd_file` is a fourth, incidental tunable for the target path (handy for testing without touching `/etc/motd`).
- `template_data` is passed explicitly so CFEngine doesn't fall back to the expensive implicit `datastate()`.
- Triple-mustache (`{{{ }}}`) avoids HTML-escaping characters like `&` in org names or contact strings.
- Verified with `cf-promises -cf`, `cfengine lint` (both clean), and two `cf-agent` runs against a scratch path — once with all three augments set, once with none. The `chown` errors in those runs were only because the test ran as a non-root user; `perms => mog(...)` applies cleanly when the agent runs as root against `/etc/motd`.