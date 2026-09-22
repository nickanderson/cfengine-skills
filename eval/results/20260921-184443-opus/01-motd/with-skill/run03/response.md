Three files written to `/tmp/cfeval-01-motd-with-skill.cISKXwa3/work`, all mode 600. Validated with `cf-promises --full-check` and exercised with `cf-agent` both with and without `def.json` to confirm the augments overrides and the in-policy defaults.

The three independent tunables are `def.motd_organization`, `def.motd_support_contact`, and `def.motd_legal_notice`.

**`motd.cf`**

```cfengine3
bundle agent motd
#@brief Manage the content of the message of the day (/etc/motd)
#
# Three independent tunables, each overridable from augments (def.json):
#
#   def.motd_organization    - Organization name shown in the banner
#   def.motd_support_contact - Who to contact for help with this host
#   def.motd_legal_notice    - Legal / acceptable use notice
{
  vars:
      # Tunables. The policy reads from the def bundle when the augments
      # variable is defined, otherwise it falls back to the default here.

      "c[organization]"
        string => ifelse(isvariable("def.motd_organization"),
                         "$(def.motd_organization)",
                         "Example Organization");

      "c[support_contact]"
        string => ifelse(isvariable("def.motd_support_contact"),
                         "$(def.motd_support_contact)",
                         "support@example.com");

      "c[legal_notice]"
        string => ifelse(isvariable("def.motd_legal_notice"),
                         "$(def.motd_legal_notice)",
                         "Authorized use only. Activity may be monitored.");

      # Host facts rendered alongside the tunables.
      "c[fqhost]" string => "$(sys.fqhost)";
      "c[flavor]" string => "$(sys.flavor)";
      "c[arch]"   string => "$(sys.arch)";

      # Build the template data from the classic array so that values
      # containing quotes or newlines cannot break the container.
      "_template_data" data => mergedata("c");

      "_template"
        string => concat(
          "$(const.n)",
          "===============================================================$(const.n)",
          " {{{organization}}}$(const.n)",
          "===============================================================$(const.n)",
          "$(const.n)",
          " Host    : {{{fqhost}}}$(const.n)",
          " System  : {{{flavor}}} ({{{arch}}})$(const.n)",
          "$(const.n)",
          " {{{legal_notice}}}$(const.n)",
          "$(const.n)",
          " Support : {{{support_contact}}}$(const.n)",
          "$(const.n)",
          " This file is managed by CFEngine. Local edits are reverted.$(const.n)",
          "===============================================================$(const.n)");

  files:
      "/etc/motd"
        create => "true",
        edit_template_string => "$(_template)",
        template_method => "inline_mustache",
        template_data => @(_template_data),
        perms => mog("0644", "root", "root"),
        handle => "motd_content",
        comment => "The message of the day informs and warns users at login";

  reports:
    inform_mode::
      "$(this.bundle): /etc/motd managed for '$(c[organization])'";
}
```

**`promises.cf`** (entry point; drop the `motd` bundle into your existing bundlesequence instead if you already have one)

```cfengine3
body common control
{
      inputs => { "$(sys.libdir)/files.cf", "motd.cf" };
      bundlesequence => { "motd" };
}
```

**`def.json`** (adjacent to the entry point; every key is optional — omit one and the policy default applies)

```json
{
  "variables": {
    "motd_organization": {
      "value": "Northern.tech",
      "comment": "Organization name shown at the top of the message of the day",
      "tags": [ "motd" ]
    },
    "motd_support_contact": {
      "value": "admin@example.com or #ops in chat",
      "comment": "Where users should go for help with this host",
      "tags": [ "motd" ]
    },
    "motd_legal_notice": {
      "value": "Authorized use only. All activity is logged and monitored.",
      "comment": "Legal / acceptable use notice presented before login shells",
      "tags": [ "motd" ]
    }
  }
}
```

Notes on a couple of judgment calls:

- The template data is assembled with `mergedata("c")` over a classic array rather than `parsejson()` on an interpolated JSON string, so a tunable containing a quote or newline can't corrupt the container. Triple-stache (`{{{ }}}`) avoids HTML-escaping characters like `&` in org names.
- `template_data` is passed explicitly, so the expensive implicit `datastate()` is never used.
- The file path is fixed at `/etc/motd` — the ask was for three variables governing *content*. If you also want the path tunable, add a fourth `def.motd_file` following the same `isvariable`/`ifelse` pattern.
- `perms => mog(...)` comes from the standard library, hence the `$(sys.libdir)/files.cf` input. If you're running this outside a masterfiles framework, drop that input and inline a local `body perms`.