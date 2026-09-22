Written to `/tmp/cfeval-01-motd-with-skill.uwrQtKtS/work/`: `promises.cf`, `motd.cf`, `def.json`.

The policy renders `/etc/motd` from an inline mustache template driven by three independent, augments-tunable settings, each with a policy default so it works with no `def.json` at all:

| Augments key | Type | Default |
|---|---|---|
| `motd_organization` | string | `Example Organization` |
| `motd_contact` | string | `support@example.com` |
| `motd_notices` | slist | one default notice line |

Validated with `cf-promises --full-check`, `cfengine lint`, and functional runs (with full augments, no augments, and a partial override); rendering is idempotent — the second run reports the file kept.

**`promises.cf`**
```cfengine3
# Policy entry point for the message of the day policy.
#
# Run standalone with:
#   cf-agent -KIf ./promises.cf
#
# Settings are tunable from the adjacent def.json (augments).

body common control
{
      bundlesequence => { "motd" };
      inputs         => { "motd.cf" };
}
```

**`motd.cf`**
```cfengine3
bundle agent motd
# @brief Manage the content of the message of the day (/etc/motd)
#
# Three independent settings drive the rendered content. Each one is tunable
# from augments (def.json) and falls back to a sane default when it is not
# defined there:
#
#   def.motd_organization -> string, organization name shown in the banner
#   def.motd_contact      -> string, support contact shown in the banner
#   def.motd_notices      -> slist,  extra notice lines appended to the banner
{
  vars:
      # --- Tunable 1: organization name -----------------------------------
      "_organization"
        string => ifelse(isvariable("def.motd_organization"),
                         "$(def.motd_organization)",
                         "Example Organization"),
        comment => "Organization name displayed at the top of the motd";

      # --- Tunable 2: support contact --------------------------------------
      "_contact"
        string => ifelse(isvariable("def.motd_contact"),
                         "$(def.motd_contact)",
                         "support@example.com"),
        comment => "Where users should go for help with this host";

      # --- Tunable 3: additional notice lines ------------------------------
      # slist, so it is collected from def.json with an explicit default.
      "_notices"
        slist => { "Unauthorized use is prohibited and may be monitored." },
        unless => isvariable("def.motd_notices"),
        comment => "Default notices when none are supplied by augments";

      "_notices"
        slist => { @(def.motd_notices) },
        if => isvariable("def.motd_notices"),
        comment => "Notices supplied by augments";

      # --- Rendering -------------------------------------------------------
      "_file"
        string => "/etc/motd",
        comment => "Location of the message of the day";

      "_notices_data"
        data => mergedata(_notices),
        comment => "The notice lines as a JSON array for the template";

      "_template_data"
        data => parsejson(format('{ "organization": "%s", "contact": "%s", "hostname": "%s", "os": "%s", "notices": %s }',
                                 "$(_organization)",
                                 "$(_contact)",
                                 "$(sys.fqhost)",
                                 "$(sys.flavor)",
                                 storejson(_notices_data))),
        comment => "Only the values the template needs, so datastate() is not used";

      "_template"
        string =>
"###############################################################################
  {{{organization}}}
###############################################################################
  Host    : {{{hostname}}}
  System  : {{{os}}}
  Support : {{{contact}}}
{{#notices}}  Notice  : {{{.}}}
{{/notices}}###############################################################################
  This file is managed by CFEngine. Local edits will be reverted.
###############################################################################
",
        comment => "Inline mustache template for the message of the day";

  files:
      "$(_file)"
        create => "true",
        perms => motd_mog("0644", "root", "root"),
        edit_template_string => "$(_template)",
        template_method => "inline_mustache",
        template_data => @(_template_data),
        classes => motd_results("bundle", "motd_content"),
        comment => "Render the motd from the three tunable settings";

  reports:
    motd_content_repaired::
      "Updated $(_file) for '$(_organization)'";

    inform_mode.motd_content_kept::
      "$(_file) is already correct for '$(_organization)'";
}

body perms motd_mog(mode, owner, group)
# @brief Set mode, owner and group
{
      mode   => "$(mode)";
      rxdirs => "false";
      owners => { "$(owner)" };
      groups => { "$(group)" };
}

body classes motd_results(scope, prefix)
# @brief Define <prefix>_(reached|kept|repaired|failed|denied|timeout) classes
{
      scope => "$(scope)";
      promise_kept     => { "$(prefix)_reached", "$(prefix)_kept" };
      promise_repaired => { "$(prefix)_reached", "$(prefix)_repaired" };
      repair_failed    => { "$(prefix)_reached", "$(prefix)_failed"  };
      repair_denied    => { "$(prefix)_reached", "$(prefix)_denied"  };
      repair_timeout   => { "$(prefix)_reached", "$(prefix)_timeout" };
}
```

**`def.json`** (adjacent to the entry point; uses the expressive `variables` form so each tunable carries a comment and tag)
```json
{
  "variables": {
    "motd_organization": {
      "value": "Northern.tech",
      "comment": "Organization name shown at the top of the message of the day",
      "tags": [ "motd" ]
    },
    "motd_contact": {
      "value": "admin@example.com",
      "comment": "Support contact shown in the message of the day",
      "tags": [ "motd" ]
    },
    "motd_notices": {
      "value": [
        "Unauthorized use is prohibited and may be monitored.",
        "This host is managed by CFEngine; open a ticket before changing it."
      ],
      "comment": "Extra notice lines appended to the message of the day",
      "tags": [ "motd" ]
    }
  }
}
```

Rendered output with the above `def.json`:

```
###############################################################################
  Northern.tech
###############################################################################
  Host    : <host>
  System  : ubuntu_24
  Support : admin@example.com
  Notice  : Unauthorized use is prohibited and may be monitored.
  Notice  : This host is managed by CFEngine; open a ticket before changing it.
###############################################################################
  This file is managed by CFEngine. Local edits will be reverted.
###############################################################################
```

Notes on a couple of judgment calls: the bodies are defined locally with a `motd_` prefix rather than pulling in `stdlib.cf`, so the policy is self-contained and won't collide with stdlib if you drop it into masterfiles; and the destination path is a plain variable rather than a fourth tunable, to keep exactly three configurable settings as asked — promote it to `def.motd_file` with the same `isvariable`/`ifelse` pattern if you want it overridable.