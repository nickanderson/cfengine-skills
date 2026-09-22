Validated with `cf-promises -cf`, `cfengine lint`, and an actual `cf-agent` run against a temp path (both with and without `def.json`, confirming the defaults path works). Files written to the working directory: `promises.cf`, `motd.cf`, `def.json`.

The three independent tunables are `motd_organization`, `motd_legal_notice`, and `motd_support_contact`. Each is instrumented with the `isvariable()` + `ifelse()` pattern so the policy has a working default and augments can override any subset of them.

**`motd.cf`**

```cfengine3
bundle agent motd
# @brief Manage the content of the message of the day (/etc/motd)
#
# Three independent settings drive the rendered message. Each is tunable from
# augments (def.json) and falls back to a policy default when the augments
# variable is not defined:
#
#   def.motd_organization    - organization that owns the host
#   def.motd_legal_notice    - access notice presented at login
#   def.motd_support_contact - where to direct questions about the host
{
  vars:

      "organization"
        string => ifelse(isvariable("default:def.motd_organization"),
                         "$(default:def.motd_organization)",
                         "Example Organization"),
        comment => "Name of the organization that owns this host";

      "legal_notice"
        string => ifelse(isvariable("default:def.motd_legal_notice"),
                         "$(default:def.motd_legal_notice)",
                         "Authorized use only. Activity may be monitored and reported."),
        comment => "Access notice displayed to anyone logging in";

      "support_contact"
        string => ifelse(isvariable("default:def.motd_support_contact"),
                         "$(default:def.motd_support_contact)",
                         "support@example.com"),
        comment => "Where users should direct questions about this host";

      "_content"
        string =>
"===============================================================================
  $(organization)
===============================================================================

  $(legal_notice)

  Hostname : $(sys.fqhost)
  Platform : $(sys.flavor) ($(sys.arch))
  Support  : $(support_contact)

  This host is managed by CFEngine. Local edits to /etc/motd are reverted.
===============================================================================
",
        comment => "The fully rendered message of the day";

  files:

      "/etc/motd"
        create => "true",
        content => "$(_content)",
        perms => mog("0644", "root", "root"),
        comment => "The message of the day is presented at login and should
                    accurately state who owns the host, the terms of its use,
                    and where to get help.";

  reports:

    verbose_mode::
      "Rendered /etc/motd for '$(organization)' (support: $(support_contact))";
}
```

**`def.json`** (must sit adjacent to the policy entry point)

```json
{
  "variables": {
    "motd_organization": {
      "value": "Northern.tech",
      "comment": "Organization that owns hosts managed by this policy set",
      "tags": [ "motd" ]
    },
    "motd_legal_notice": {
      "value": "Authorized use only. All activity on this system is logged and may be reviewed.",
      "comment": "Access notice presented at login",
      "tags": [ "motd" ]
    },
    "motd_support_contact": {
      "value": "admin@example.com",
      "comment": "Contact for questions or incidents relating to this host",
      "tags": [ "motd" ]
    }
  }
}
```

**`promises.cf`** (standalone entry point for testing; if you're dropping `motd.cf` into an existing policy set instead, add it to `inputs` and the bundlesequence there rather than using this file)

```cfengine3
body common control
{
      bundlesequence => { "motd" };

      inputs => {
                  "$(sys.libdir)/stdlib.cf",
                  "motd.cf",
                };
}
```

Notes on the choices:
- `content` is used rather than a mustache template because every substitution is a plain string — this avoids the JSON-escaping fragility of interpolating user-supplied values into `parsejson()`, and avoids the implicit `datastate()` cost.
- `mog` comes from `stdlib.cf`; under the Masterfiles Policy Framework it's already in `inputs`, so drop that line from `inputs` if you're integrating there.
- Policy files are mode 600 as `cf-agent` requires.
- Per-host overrides work the same way through `host_specific.json` (CMDB), which takes precedence over `def.json`.