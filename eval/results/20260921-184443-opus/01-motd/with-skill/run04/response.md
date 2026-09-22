Wrote `motd.cf` and `def.json` to the working directory. Both pass `cf-promises --full-check`, and I verified the rendering end-to-end with `cf-agent` twice — once with no `def.json` (policy defaults) and once with it (augments overrides) — confirming the tunables actually take effect.

The three independent tunables are `def.motd_organization`, `def.motd_support_contact`, and `def.motd_banner`. Each is instrumented with the `isvariable()` + `ifelse()` pattern so the policy works standalone with no augments at all.

## `motd.cf`

```cfengine3
bundle common motd_meta
# @brief Metadata for the motd policy
{
  meta:
      "description"
        string => "Manage /etc/motd content from three augments-tunable values.";

      "tags" slist => { "motd", "banner", "compliance" };
}

bundle agent motd
# @brief Manage the message of the day
#
# Three independent tunables, each overridable from augments (def.json):
#
#   def.motd_organization    - Organization name shown in the banner header
#   def.motd_support_contact - Where users should go for help
#   def.motd_banner          - Access/authorization notice body
#
# Any tunable left undefined in augments falls back to the policy default
# below, so the policy is useful with an empty def.json.
{
  vars:
      # --- Tunable 1: organization name ---------------------------------
      "_organization"
        string => ifelse(isvariable("def.motd_organization"),
                         "$(def.motd_organization)",
                         "Example Organization"),
        comment => "Set def.motd_organization in def.json to override.";

      # --- Tunable 2: support contact -----------------------------------
      "_support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                         "$(def.motd_support_contact)",
                         "support@example.com"),
        comment => "Set def.motd_support_contact in def.json to override.";

      # --- Tunable 3: access banner text --------------------------------
      "_banner"
        string => ifelse(isvariable("def.motd_banner"),
                         "$(def.motd_banner)",
                         "Unauthorized access to this system is prohibited. All activity may be monitored and recorded."),
        comment => "Set def.motd_banner in def.json to override.";

      # --- Rendering ----------------------------------------------------
      "_motd_file" string => "/etc/motd";

      "_template_lines"
        slist => {
                   "*******************************************************************",
                   " {{{organization}}}",
                   "*******************************************************************",
                   "",
                   " {{{banner}}}",
                   "",
                   " Host    : {{{fqhost}}}",
                   " Platform: {{{ostype}}}",
                   " Support : {{{support_contact}}}",
                   "",
                   " Managed by CFEngine. Local edits to this file are reverted.",
                   "",
                 };

      "_template" string => join("$(const.n)", "_template_lines");

      # Only the values the template needs -- avoids the implicit, expensive
      # datastate() expansion.
      "_template_data"
        data => parsejson('{
                            "organization": "$(_organization)",
                            "support_contact": "$(_support_contact)",
                            "banner": "$(_banner)",
                            "fqhost": "$(sys.fqhost)",
                            "ostype": "$(sys.ostype)"
                          }');

  files:
      "$(_motd_file)"
        create => "true",
        perms => motd_mog("0644", "root", "root"),
        edit_template_string => "$(_template)",
        template_method => "inline_mustache",
        template_data => @(_template_data),
        classes => motd_results("motd_file"),
        comment => "Render the message of the day from the three tunables";

  reports:
    motd_file_repaired::
      "$(this.bundle): updated $(_motd_file) for '$(_organization)'";

    motd_file_failed::
      "$(this.bundle): FAILED to update $(_motd_file)";

    inform_mode.!(motd_file_repaired|motd_file_failed)::
      "$(this.bundle): $(_motd_file) is already correct";
}

body perms motd_mog(mode, user, group)
# @brief Set mode, owner and group
{
      mode  => "$(mode)";
      owners => { "$(user)" };
      groups => { "$(group)" };
      rxdirs => "false";
}

body classes motd_results(prefix)
# @brief Define namespace-scoped outcome classes with a common prefix
{
      promise_repaired => { "$(prefix)_repaired" };
      repair_failed    => { "$(prefix)_failed" };
      repair_denied    => { "$(prefix)_failed" };
      repair_timeout   => { "$(prefix)_failed" };
      scope            => "namespace";
}

#
# Standalone entry point. Remove this body (and add "motd.cf" to the inputs of
# your promises.cf) when integrating into an existing policy set -- only policy
# entry points may carry `body common control`.
#
body common control
{
      bundlesequence => { "motd" };
}
```

## `def.json`

```json
{
  "variables": {
    "motd_organization": {
      "value": "Northern.tech",
      "comment": "Tunable 1: organization name rendered in the motd header",
      "tags": [ "motd" ]
    },
    "motd_support_contact": {
      "value": "admin@example.com or x4357",
      "comment": "Tunable 2: where users should go for help",
      "tags": [ "motd" ]
    },
    "motd_banner": {
      "value": "This system is for authorized use only. All activity may be monitored and recorded.",
      "comment": "Tunable 3: access/authorization notice body",
      "tags": [ "motd" ]
    }
  }
}
```

Notes on a few choices:

- `def.json` must sit adjacent to the **policy entry point** to be loaded. Standalone that's next to `motd.cf`; integrated, it belongs next to `promises.cf`.
- `template_data` is passed explicitly with only the five keys the template needs, rather than letting `datastate()` serialize everything in scope.
- The `{{{triple}}}` mustache form is used so ampersands and quotes in an organization name or banner aren't HTML-escaped.
- Both files are mode 600, as `cf-agent` requires.
- Running it as a non-root user will fail the `chown` to `root:root` — that's expected, since `/etc/motd` is root-owned anyway.