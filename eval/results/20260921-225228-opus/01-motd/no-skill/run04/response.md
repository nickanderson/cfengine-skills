Written to the working directory: `motd.cf`, `def.json`, `standalone.cf`, `README.md`.

The three independent, augments-configurable variables are `def.motd_banner`, `def.motd_message`, and `def.motd_contact`. Each is defined with an in-policy default guarded by `unless => isvariable(...)` and an augments value guarded by `if => isvariable(...)`, so any subset can be overridden and the policy still works with no `def.json` at all. Content is rendered with an inline mustache template fed from `datastate()`, which avoids any JSON-escaping hazard from quotes or newlines in the augments values.

**motd.cf**

```cfengine3
body file control
# @brief Pull in the standard library for the mog() and results() bodies
#
# When this policy is loaded from the Masterfiles Policy Framework stdlib.cf is
# already in inputs; listing the same path again is harmless.
{
      inputs => { "$(sys.libdir)/stdlib.cf" };
}

bundle agent motd
# @brief Manage the content of the message of the day (/etc/motd)
#
# The content is driven by three independent variables, each of which can be
# set from an augments file (def.json):
#
#   def.motd_banner    Headline printed at the top of the motd
#   def.motd_message   Body text, e.g. the site usage/authorization statement
#   def.motd_contact   Who to contact about this host
#
# Each variable falls back to a reasonable default when it is not defined in
# augments, so the policy is safe to run with no def.json at all, and any
# subset of the three may be overridden.
{
  vars:

      # --- 1. Banner -------------------------------------------------------

      "banner"
        string  => "Welcome to $(sys.uqhost)",
        unless  => isvariable( "def.motd_banner" ),
        comment => "Default headline, used when augments does not set one.";

      "banner"
        string  => "$(def.motd_banner)",
        if      => isvariable( "def.motd_banner" ),
        comment => "Headline supplied by def.json.";

      # --- 2. Message ------------------------------------------------------

      "message"
        string  => "Authorized use only. All activity on this system may be monitored and recorded.",
        unless  => isvariable( "def.motd_message" ),
        comment => "Default body text, used when augments does not set one.";

      "message"
        string  => "$(def.motd_message)",
        if      => isvariable( "def.motd_message" ),
        comment => "Body text supplied by def.json.";

      # --- 3. Contact ------------------------------------------------------

      "contact"
        string  => "root@$(sys.fqhost)",
        unless  => isvariable( "def.motd_contact" ),
        comment => "Default contact address, used when augments does not set one.";

      "contact"
        string  => "$(def.motd_contact)",
        if      => isvariable( "def.motd_contact" ),
        comment => "Contact address supplied by def.json.";

      # --- Rendering -------------------------------------------------------

      "template"
        string  => "###############################################################################
 {{{vars.motd.banner}}}
###############################################################################

{{{vars.motd.message}}}

  Hostname : {{{vars.sys.fqhost}}}
  Address  : {{{vars.sys.ipv4}}}
  Platform : {{{vars.sys.ostype}}} ({{{vars.sys.arch}}})
  Contact  : {{{vars.motd.contact}}}

This file is managed by CFEngine. Local modifications will be reverted.
",
        comment => "Inline mustache template combining the three variables with
                    a few facts about the host. Triple mustaches are used so
                    that punctuation in the values is not HTML escaped.";

      "state"
        data    => datastate(),
        comment => "Data used to expand the template. Using datastate() rather
                    than hand built JSON means quotes or other special
                    characters in the augments values cannot break the policy.";

  files:

      "/etc/motd"
        create               => "true",
        edit_template_string => "$(template)",
        template_method      => "inline_mustache",
        template_data        => @(state),
        perms                => mog( "0644", "root", "root" ),
        classes              => results( "bundle", "motd_file" ),
        comment              => "The message of the day is owned by policy, so
                                 it is rendered from the template on every run
                                 and local edits are converged away.";

  reports:

    motd_file_repaired::
      "Updated /etc/motd";

    motd_file_failed|motd_file_denied::
      "Unable to update /etc/motd";

    DEBUG|DEBUG_motd::
      "DEBUG $(this.bundle): banner  = '$(banner)'";
      "DEBUG $(this.bundle): message = '$(message)'";
      "DEBUG $(this.bundle): contact = '$(contact)'";
}
```

**def.json**

```json
{
  "variables": {
    "motd_banner": "ACME Corp - Production Infrastructure",
    "motd_message": "Authorized use only.\n\nThis system is managed by CFEngine; changes made by hand are not durable.\nAll activity on this system is logged and may be reviewed.",
    "motd_contact": "ops@example.com"
  }
}
```

**standalone.cf** (test entry point; `def.json` beside it is auto-loaded)

```cfengine3
body common control
# @brief Entry point for testing motd.cf on its own
#
#   cf-agent -KIf ./standalone.cf
#
# def.json in this same directory is picked up automatically because augments
# are read from the directory of the policy entry file.
{
      bundlesequence => { "motd" };
      inputs         => { "$(sys.policy_entry_dirname)/motd.cf" };
}
```

Verified with cf-promises/cf-agent 3.27.1 (using a temporary copy pointed at `/tmp` so it could run unprivileged): full augments override, no `def.json` at all, partial override (contact only), and a convergent second run with no further repair. Two notes: `default()` is not a CFEngine function, hence the `if`/`unless` pair per variable; and the inline template must be attached with `edit_template_string`, not `edit_template`, which requires CFEngine 3.18+.

For MPF deployment, put `motd.cf` in `services/`, add it to `inputs` and the bundlesequence, and merge the `variables` block into `masterfiles/def.json` — details in `README.md`.