Validated with `cf-promises --full-check` and `cfengine lint`, and test-rendered with `cf-agent` against a sandbox path — confirmed both the augments-supplied values and the built-in defaults render correctly.

## `motd.cf`

```cfengine3
bundle agent motd
{
  meta:
      "description"
        string => "Manage the content of the message of the day.";

      "tunables"
        slist => {
                   "def.motd_organization",
                   "def.motd_support_contact",
                   "def.motd_banner",
                 };

  vars:

    # The three tunables. Each one is independent and individually overridable
    # from augments (def.json). The policy falls back to a sane default when the
    # augments variable is not defined.

      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                         "$(def.motd_organization)",
                         "Acme Corp"),
        comment => "Organization name shown in the motd banner header.";

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                         "$(def.motd_support_contact)",
                         "support@example.com"),
        comment => "Where users should go for help with this host.";

      "banner"
        string => ifelse(isvariable("def.motd_banner"),
                         "$(def.motd_banner)",
                         "Authorized use only. All activity may be monitored and recorded."),
        comment => "Legal/acceptable-use notice shown in the motd.";

    # Implementation details, not tunable.

      "_file"
        string => "/etc/motd";

      "_group"
        string => ifelse("freebsd|openbsd|netbsd|darwin", "wheel", "root");

    # Only the values the template needs, so the implicit (and expensive)
    # datastate() is not used to render the template.

      "_template_data"
        data => parsejson('{
                             "organization": "$(organization)",
                             "support_contact": "$(support_contact)",
                             "banner": "$(banner)",
                             "fqhost": "$(sys.fqhost)",
                             "platform": "$(sys.flavour)"
                           }');

      "_template"
        string => concat(
                    "################################################################$(const.n)",
                    "  {{{organization}}}$(const.n)",
                    "################################################################$(const.n)",
                    "$(const.n)",
                    "  {{{banner}}}$(const.n)",
                    "$(const.n)",
                    "  Host     : {{{fqhost}}}$(const.n)",
                    "  Platform : {{{platform}}}$(const.n)",
                    "  Support  : {{{support_contact}}}$(const.n)",
                    "$(const.n)",
                    "################################################################$(const.n)");

  files:

      "$(_file)"
        create => "true",
        perms => mog("0644", "root", "$(_group)"),
        template_method => "inline_mustache",
        edit_template_string => "$(_template)",
        template_data => @(_template_data),
        classes => results("bundle", "_motd"),
        comment => "Render the message of the day from the tunable values.";

  reports:

    _motd_repaired::
      "Updated '$(_file)' for organization '$(organization)'";

    _motd_not_kept|_motd_failed::
      "Failed to update '$(_file)'";

    DEBUG|DEBUG_motd::
      "DEBUG $(this.bundle): organization    = '$(organization)'";
      "DEBUG $(this.bundle): support_contact = '$(support_contact)'";
      "DEBUG $(this.bundle): banner          = '$(banner)'";
}
```

## `promises.cf`

```cfengine3
# Policy entry point for message of the day management.
#
# def.json (adjacent to this file) supplies the tunable values.

body common control
{
      bundlesequence => { "motd" };

      inputs => {
                  "$(sys.libdir)/stdlib.cf",   # mog(), results()
                  "motd.cf",
                };
}
```

## `def.json`

```json
{
  "variables": {
    "motd_organization": {
      "value": "Northern.tech",
      "comment": "Organization name shown in the message of the day header.",
      "tags": [ "motd" ]
    },
    "motd_support_contact": {
      "value": "admin@example.com or x5555",
      "comment": "Where users of this host should go for help.",
      "tags": [ "motd" ]
    },
    "motd_banner": {
      "value": "Authorized use only. All activity may be monitored and recorded.",
      "comment": "Legal/acceptable-use notice shown in the message of the day.",
      "tags": [ "motd" ]
    }
  }
}
```

Notes on the design:

- **Three independent tunables** — `def.motd_organization`, `def.motd_support_contact`, `def.motd_banner`. Each is instrumented separately with the `isvariable()` + `ifelse()` pattern, so overriding one in augments does not disturb the other two; anything left out of `def.json` keeps its policy default.
- Since `def.json` `vars`/`variables` land in `default:def`, the same three keys can equally be supplied by `host_specific.json` CMDB data or by a recursively included augments file.
- `template_data` is passed explicitly with only the five values the template needs, avoiding the implicit `datastate()` serialization.
- Triple-mustache (`{{{ }}}`) is used so values containing `&`, `<`, or `>` are not HTML-escaped. The one assumption worth flagging: the tunable values are interpolated into a JSON string for `parsejson()`, so a value containing a literal double quote or backslash would need escaping — plain prose, email addresses, and hostnames are fine.
- If you drop this into a cfbs/masterfiles project instead of running it standalone, remove `promises.cf` and add `motd.cf` to your existing `inputs` and `motd` to the bundlesequence — stdlib is already loaded there.