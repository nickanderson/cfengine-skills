Wrote `motd.cf` and `def.json` to the working directory and validated both against the local CFEngine 3.27.1 (syntax check, render with defaults, render with full and partial augments, and a second run to confirm convergence — tested against a temp path so `/etc/motd` was not touched).

Three independent settings drive the content, each overridable from augments and each with its own fallback: `def.motd_banner`, `def.motd_message`, `def.motd_contact`. Note that `default()` is not a function in this release, so the policy uses the `if`/`unless => isvariable(...)` idiom instead. Augments only define variables in the `default:def.` namespace — bundle-qualified entries like `default:motd.banner` are ignored (I verified this), which is why the tunables are `def.motd_*`.

**motd.cf**

```cfengine3
bundle agent main
# @brief Entry bundle for standalone testing: cf-agent -KI -f ./motd.cf
{
  methods:

      "Manage the message of the day"
        usebundle => motd;
}

bundle agent motd
# @brief Manage the content of /etc/motd
#
# The rendered content is driven by three independent settings, each of which
# can be overridden from augments (def.json) and each of which falls back to a
# built in default when it is not defined:
#
#   def.motd_banner   - greeting shown on the first line
#   def.motd_message  - body text (may contain embedded newlines)
#   def.motd_contact  - administrative contact shown in the footer
#
# Override any one, any two, all three, or none of them.
{
  vars:

    # -- 1: banner ----------------------------------------------------------
      "banner"
        string  => "$(def.motd_banner)",
        if      => isvariable( "def.motd_banner" ),
        comment => "Greeting from augments";

      "banner"
        string  => "Welcome to $(sys.fqhost)",
        unless  => isvariable( "def.motd_banner" ),
        comment => "Built in default greeting";

    # -- 2: message ---------------------------------------------------------
      "message"
        string  => "$(def.motd_message)",
        if      => isvariable( "def.motd_message" ),
        comment => "Body text from augments";

      "message"
        string  => "This host is managed by CFEngine. Local modifications to $(motd_file) will be reverted.",
        unless  => isvariable( "def.motd_message" ),
        comment => "Built in default body text";

    # -- 3: contact ---------------------------------------------------------
      "contact"
        string  => "$(def.motd_contact)",
        if      => isvariable( "def.motd_contact" ),
        comment => "Administrative contact from augments";

      "contact"
        string  => "root@$(sys.fqhost)",
        unless  => isvariable( "def.motd_contact" ),
        comment => "Built in default administrative contact";

    # -- implementation details (not intended to be tuned) ------------------

      "motd_file"
        string => "/etc/motd";

      "motd_data"
        data => mergedata( '{ "banner":  "$(banner)",
                              "message": "$(message)",
                              "contact": "$(contact)",
                              "fqhost":  "$(sys.fqhost)" }' ),
        comment => "Data used to render the template";

      "template"
        string => concat( "### This file is managed by CFEngine. Local edits will be lost. ###$(const.n)",
                          "$(const.n)",
                          "{{{banner}}}$(const.n)",
                          "$(const.n)",
                          "{{{message}}}$(const.n)",
                          "$(const.n)",
                          "-- $(const.n)",
                          "Host:    {{{fqhost}}}$(const.n)",
                          "Contact: {{{contact}}}$(const.n)" ),
        comment => "Inline mustache template for the motd";

  files:

      "$(motd_file)"
        create               => "true",
        perms                => motd_perms( "0644", "root", "root" ),
        template_method      => "inline_mustache",
        template_data        => @(motd_data),
        edit_template_string => "$(template)",
        comment              => "The message of the day is rendered from the three motd settings",
        handle               => "motd_files_motd";

  reports:

    DEBUG|DEBUG_motd::
      "DEBUG $(this.bundle): banner  = '$(banner)'";
      "DEBUG $(this.bundle): message = '$(message)'";
      "DEBUG $(this.bundle): contact = '$(contact)'";
}

body perms motd_perms(mode, user, group)
# @brief Set mode, owner and group on a file
# @param mode Numeric or symbolic file mode
# @param user Owning user
# @param group Owning group
{
      mode   => "$(mode)";
      owners => { "$(user)" };
      groups => { "$(group)" };
      rxdirs => "false";
}

body common control
# @brief Standalone entry point. Remove this body when including motd.cf in an
#        existing policy set (add motd.cf to inputs and call the motd bundle).
{
      bundlesequence => { "main" };
}
```

**def.json**

```json
{
  "variables": {
    "motd_banner": "*** ACME Corp - Production ***",
    "motd_message": "Authorized use only. All activity on this system is logged and monitored.\n\nScheduled maintenance window: Sundays 02:00-04:00 UTC.",
    "motd_contact": "ops@example.com"
  }
}
```

Usage notes:
- Standalone: `cf-agent -KI -f ./motd.cf` (def.json is read from the same directory as the policy file). Add `-D DEBUG` to print the three resolved values.
- In a policy set: delete the `body common control` block, add `motd.cf` to your inputs, call `usebundle => motd`, and put the three `motd_*` keys in your masterfiles `def.json`.
- JSON `\n` in `motd_message` renders as real newlines; mustache triple-braces avoid HTML escaping of characters like `&`.