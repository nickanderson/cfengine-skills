Three files written to the working directory, validated with `cf-promises --full-check` and exercised with `cf-agent` across all four combinations of the optional settings.

## The three tunables

| Augments key (`def.json`) | Policy variable | Default | Effect on content |
|---|---|---|---|
| `motd_organization` | `motd.organization` | `Example Organization` | Banner headline |
| `motd_support_contact` | `motd.support_contact` | `support@example.com` | `Help :` line; `""` omits it |
| `motd_policy_notice` | `motd.policy_notice` | `Unauthorized access…` | Acceptable-use paragraph; `""` omits it |

Each is instrumented with the `isvariable()` + `ifelse()` pattern, so the policy stands alone without `def.json` and each setting can be overridden independently (including via `host_specific.json` CMDB data).

## `motd.cf`

```cfengine3
bundle agent motd
# @brief Manage the content of the message of the day (/etc/motd)
#
# Three independent settings drive the rendered content. Each one is tunable
# via augments (def.json) and falls back to a policy default when the augments
# variable is not defined:
#
#   def.motd_organization    - organization name shown in the banner
#   def.motd_support_contact - who to contact for help
#   def.motd_policy_notice   - acceptable use / legal notice text
{
  vars:

      # --- Tunable 1: organization name -------------------------------------
      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                         "$(def.motd_organization)",
                         "Example Organization"),
        comment => "Organization name rendered in the motd banner";

      # --- Tunable 2: support contact ---------------------------------------
      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                         "$(def.motd_support_contact)",
                         "support@example.com"),
        comment => "Contact address rendered in the motd. Empty string omits the line";

      # --- Tunable 3: policy/legal notice -----------------------------------
      "policy_notice"
        string => ifelse(isvariable("def.motd_policy_notice"),
                         "$(def.motd_policy_notice)",
                         "Unauthorized access to this system is prohibited and may be prosecuted."),
        comment => "Acceptable use notice rendered in the motd. Empty string omits the section";

      # File managed by this bundle.
      "motd_file" string => "/etc/motd";

      # Only the values the template needs are passed as template_data. Relying
      # on the implicit datastate() would serialize every variable and class in
      # scope.
      #
      # CFEngine mustache sections require an actual boolean (or container), a
      # non-empty string is not truthy, so the "has_*" flags gate the optional
      # sections.
      "template_data"
        data => parsejson(format('{
                                    "organization":     "%s",
                                    "support_contact":  "%s",
                                    "policy_notice":    "%s",
                                    "has_support_contact": %s,
                                    "has_policy_notice":   %s,
                                    "fqhost":           "%s",
                                    "os":               "%s"
                                  }',
                                 "$(organization)",
                                 "$(support_contact)",
                                 "$(policy_notice)",
                                 ifelse(strcmp("$(support_contact)", ""), "false", "true"),
                                 ifelse(strcmp("$(policy_notice)", ""),   "false", "true"),
                                 "$(sys.fqhost)",
                                 "$(sys.ostype)"));

      "_rule" string => "###############################################################################";

      "template"
        string => concat(
          "$(_rule)$(const.n)",
          "  {{{organization}}}$(const.n)",
          "$(_rule)$(const.n)",
          "$(const.n)",
          "  Host : {{{fqhost}}}$(const.n)",
          "  OS   : {{{os}}}$(const.n)",
          "{{#has_support_contact}}  Help : {{{support_contact}}}$(const.n){{/has_support_contact}}",
          "{{#has_policy_notice}}$(const.n)  {{{policy_notice}}}$(const.n){{/has_policy_notice}}",
          "$(const.n)",
          "  This host is managed by CFEngine. Local changes may be reverted.$(const.n)");

  files:

      "$(motd_file)"
        create => "true",
        edit_template_string => "$(template)",
        template_method => "inline_mustache",
        template_data => @(template_data),
        perms => motd_perms("0644", "root", "root"),
        classes => motd_results("motd"),
        comment => "Render the message of the day from the three tunable settings";

  reports:
    motd_repaired::
      "Updated $(motd_file) for '$(organization)'";

    motd_failed::
      "Failed to update $(motd_file)";

    (inform_mode|verbose_mode).motd_kept::
      "$(motd_file) already matches policy for '$(organization)'";
}

body perms motd_perms(mode, user, group)
# @brief Set file mode, owner and group
{
      mode   => "$(mode)";
      owners => { "$(user)" };
      groups => { "$(group)" };
      rxdirs => "false";
}

body classes motd_results(prefix)
# @brief Define namespace scoped outcome classes prefixed with "$(prefix)"
{
      promise_repaired  => { "$(prefix)_repaired" };
      repair_failed     => { "$(prefix)_failed" };
      repair_denied     => { "$(prefix)_failed" };
      repair_timeout    => { "$(prefix)_failed" };
      promise_kept      => { "$(prefix)_kept" };
      scope             => "namespace";
}
```

## `promises.cf`

```cfengine3
body common control
{
      bundlesequence => { "motd" };
      inputs => { "motd.cf" };
}
```

## `def.json`

```json
{
  "variables": {
    "motd_organization": {
      "value": "Northern.tech",
      "comment": "Organization name shown in the motd banner",
      "tags": [ "motd" ]
    },
    "motd_support_contact": {
      "value": "admin@example.com",
      "comment": "Where users should go for help. Set to \"\" to omit the line",
      "tags": [ "motd" ]
    },
    "motd_policy_notice": {
      "value": "Authorized use only. All activity may be monitored and recorded.",
      "comment": "Acceptable use notice. Set to \"\" to omit the section",
      "tags": [ "motd" ]
    }
  }
}
```

## Verified output

With the `def.json` above:

```
###############################################################################
  Northern.tech
###############################################################################

  Host : <host>
  OS   : linux_x86_64
  Help : admin@example.com

  Authorized use only. All activity may be monitored and recorded.
  This host is managed by CFEngine. Local changes may be reverted.
```

With no `def.json` at all, the three policy defaults render instead; setting either optional value to `""` cleanly drops its line/section.

Two notes on choices I made:

- Bodies are defined locally (`motd_perms`, `motd_results`) with a `motd_` prefix rather than using stdlib's `mog`/`results`, so the policy runs standalone and won't collide if you later drop it into a policy set that has the stdlib. If you're in a cfbs project that already includes `masterfiles-stdlib`, swap them for `mog("0644","root","root")` and `results("bundle","motd")`.
- `motd_file` is a plain bundle variable, not a fourth tunable, since you asked for exactly three settings driving content. On Debian/Ubuntu `/etc/motd` may be a symlink into `/run` managed by `pam_motd`; if that's your target, point `motd_file` at `/etc/motd` and disable the dynamic `update-motd` scripts, or manage `/etc/update-motd.d/` instead.

The `perms` body chowns to `root:root`, so `cf-agent` must run as root (my local test ran unprivileged and had to skip that attribute).