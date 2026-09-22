Done. Three files in the working directory, lint-clean and verified by actually rendering the output against a temp path (defaults, augments overrides, empty message, and values containing quotes/backslashes), plus a second run to confirm the promise converges.

**`promises.cf`** — policy entry point (`def.json` must sit adjacent to it for augments to load):

```cfengine3
###############################################################################
#
# promises.cf - Policy entry point
#
# Manages the message of the day (/etc/motd). The content is driven by three
# independent variables, each overridable from augments (def.json).
#
###############################################################################

body common control
{
      bundlesequence => { "motd" };
      inputs => { "services/motd.cf" };
}
```

**`services/motd.cf`**:

```cfengine3
###############################################################################
#
# services/motd.cf - Manage the message of the day
#
# The content is built from three independent variables, each of which can be
# overridden from augments (def.json) without editing this policy:
#
#   def.motd_organization    - organization name shown in the banner
#   def.motd_support_contact - who users should contact for help
#   def.motd_message         - free form message body (set to "" to omit)
#
# Each falls back to a policy default when it is not defined in augments.
#
###############################################################################

bundle agent motd
{
  vars:

      # --- Tunable 1 of 3: organization name -------------------------------
      "organization"
        string  => ifelse(isvariable("def.motd_organization"),
                          "$(def.motd_organization)",
                          "Example Organization"),
        comment => "Organization name rendered in the MOTD banner";

      # --- Tunable 2 of 3: support contact ---------------------------------
      "support_contact"
        string  => ifelse(isvariable("def.motd_support_contact"),
                          "$(def.motd_support_contact)",
                          "support@example.com"),
        comment => "Address or phone number users should contact for help";

      # --- Tunable 3 of 3: free form message -------------------------------
      "message"
        string  => ifelse(isvariable("def.motd_message"),
                          "$(def.motd_message)",
                          "Unauthorized access to this system is prohibited."),
        comment => "Free form body text, rendered only when it is not empty";

      # Location of the file is an OS detail, not a site preference.
      "motd_file"
        string  => ifelse("windows", "$(sys.winsysdir)\motd.txt", "/etc/motd");

      # Build the template data from a classic array so that any character in
      # the tunables (quotes, backslashes, newlines) is JSON escaped for us
      # instead of being pasted into a JSON string by hand.
      "_t[organization]"    string => "$(organization)";
      "_t[support_contact]" string => "$(support_contact)";
      "_t[message]"         string => "$(message)";
      "_t[fqhost]"          string => "$(sys.fqhost)";
      "_t[os]"              string => "$(sys.ostype)";

      # A mustache section needs a real boolean, not a truthy string, so the
      # "do we have a message?" decision is made here in policy.
      "template_data"
        data    => mergedata("_t",
                             format('{ "has_message": %s }',
                                    ifelse(strcmp("$(message)", ""),
                                           "false",
                                           "true"))),
        comment => "Exactly the values the template needs, so that the
                    implicit and expensive datastate() is not used";

      "template"
        string  => concat( "$(const.n)",
                           "  {{{organization}}}$(const.n)",
                           "  ======================================$(const.n)",
                           "$(const.n)",
                           "  Host:    {{{fqhost}}} ({{{os}}})$(const.n)",
                           "  Support: {{{support_contact}}}$(const.n)",
                           "$(const.n)",
                           "{{#has_message}}$(const.n)",
                           "  {{{message}}}$(const.n)",
                           "$(const.n)",
                           "{{/has_message}}",
                           "  This system is managed by CFEngine.",
                           " Local edits to this file will be reverted.$(const.n)",
                           "$(const.n)" ),
        comment => "Inline mustache template for the message of the day.
                    It is deliberately free of timestamps so that the promise
                    converges and does not repair on every agent run";

  files:

      "$(motd_file)"
        create               => "true",
        edit_template_string => "$(template)",
        template_method      => "inline_mustache",
        template_data        => @(template_data),
        perms                => motd_perms,
        handle               => "motd_content_managed",
        comment              => "The message of the day tells users who owns
                                 this system and how to get help with it";

  reports:

    inform_mode::
      "Managing '$(motd_file)' for organization '$(organization)'";
}

body perms motd_perms
# @brief World readable, owned by root, writable only by its owner
{
      mode => "0644";

    !windows::
      owners => { "root" };
      groups => { "root" };
}
```

**`def.json`** — the augments that override the three tunables:

```json
{
  "variables": {
    "motd_organization": {
      "value": "Northern.tech",
      "comment": "Organization name rendered in the MOTD banner",
      "tags": [ "motd" ]
    },
    "motd_support_contact": {
      "value": "admin@example.com (+47 000 00 000)",
      "comment": "Where users should go for help with this host",
      "tags": [ "motd" ]
    },
    "motd_message": {
      "value": "Authorized use only. All activity may be monitored and recorded.",
      "comment": "Free-form MOTD body; set to \"\" to omit the block entirely",
      "tags": [ "motd" ]
    }
  }
}
```

Notes on the choices:

- **Independence** — each variable is instrumented separately with the `isvariable()` + `ifelse()` pattern, so you can set one, two, or all three in augments; the rest keep their policy defaults. Verified: a `def.json` setting only `motd_organization` and `motd_message` left `support_contact` at `support@example.com`.
- **The file path is not a tunable.** It's derived from the OS rather than exposed, so the count of site-configurable variables stays at the three you asked for. Say the word if you want it as a fourth.
- **`template_data` is explicit** rather than falling back to the implicit `datastate()`, and it's built by merging a classic array so a value like `Acme "Quoted" Corp \ Ltd` is escaped correctly instead of breaking the JSON.
- **`has_message` is a real boolean** — CFEngine's mustache rejects a truthy string as a section value (it errors, it doesn't just skip), so an empty `motd_message` cleanly drops the whole block.
- **No timestamp in the content**, so the promise is convergent; the second run made no changes.
- Policy files are mode `600` as `cf-agent` requires.

To deploy, drop these into your masterfiles (or `cfbs add ./services/motd.cf`) and merge the three keys into your existing `def.json` rather than replacing it.