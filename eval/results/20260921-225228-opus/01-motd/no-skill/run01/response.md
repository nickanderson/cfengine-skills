Wrote `motd.cf` and `def.json` to the working directory, validated with `cf-promises`, and functionally tested both with and without augments (path redirected to a temp dir for the test so `/etc/motd` was not touched). Both runs converged on the second pass with no repairs.

## `motd.cf`

```cfengine3
bundle agent motd
# @brief Manage the content of the message of the day
#
# The rendered file looks like this:
#
#     <banner>
#
#     <message line 1>
#     <message line 2>
#
#     <footer>
#
# Each of the three components is independently configurable from augments
# (def.json) by defining the associated variable in the `variables` key:
#
#     "variables": {
#       "motd_banner":  "Property of ACME Inc.",
#       "motd_message": [ "Line one.", "Line two." ],
#       "motd_footer":  "Questions? admin@example.com"
#     }
#
# Any variable that is *not* defined in augments falls back to the default
# defined below, so the three settings are truly independent of each other.
{
  vars:

    # -----------------------------------------------------------------
    # 1/3 banner - the first line(s) of the motd
    # -----------------------------------------------------------------

      "banner"
        string  => "Welcome to $(sys.fqhost)",
        if      => not( isvariable( "default:def.motd_banner" ) ),
        comment => "Default banner, used when the policy is not augmented";

      "banner"
        string  => "$(default:def.motd_banner)",
        if      => isvariable( "default:def.motd_banner" ),
        comment => "Banner as configured from augments (def.json)";

    # -----------------------------------------------------------------
    # 2/3 message - the body, one list entry per line
    # -----------------------------------------------------------------

      "message"
        slist   => { "This system is managed by CFEngine $(sys.cf_version).",
                     "Local changes may be reverted automatically." },
        if      => not( isvariable( "default:def.motd_message" ) ),
        comment => "Default message body, used when the policy is not augmented";

      "message"
        slist   => { @(default:def.motd_message) },
        if      => isvariable( "default:def.motd_message" ),
        comment => "Message body as configured from augments (def.json)";

    # -----------------------------------------------------------------
    # 3/3 footer - the last line(s) of the motd
    # -----------------------------------------------------------------

      "footer"
        string  => "Report issues to root@$(sys.fqhost).",
        if      => not( isvariable( "default:def.motd_footer" ) ),
        comment => "Default footer, used when the policy is not augmented";

      "footer"
        string  => "$(default:def.motd_footer)",
        if      => isvariable( "default:def.motd_footer" ),
        comment => "Footer as configured from augments (def.json)";

    # -----------------------------------------------------------------
    # Rendering
    # -----------------------------------------------------------------

      "path"
        string  => "/etc/motd",
        comment => "Location of the message of the day";

      "body"
        string  => join( "$(const.n)", "message" ),
        comment => "The message lines, one per line";

      "content"
        string  => "$(banner)$(const.n)$(const.n)$(body)$(const.n)$(const.n)$(footer)$(const.n)",
        comment => "Full, final content of the message of the day";

  files:

      "$(path)"
        create        => "true",
        content       => "$(content)",
        perms         => motd_perms( "0644", "root", "root" ),
        handle        => "motd_content",
        comment       => "The message of the day informs users about the state
                          and the acceptable use of the system, so it must hold
                          exactly the content we have assembled.";

  reports:

    verbose_mode::
      "$(this.bundle): rendering '$(path)'";
      "$(this.bundle): banner = '$(banner)'";
      "$(this.bundle): message = '$(message)'";
      "$(this.bundle): footer = '$(footer)'";
}

body perms motd_perms(mode, user, group)
# @brief Set mode, owner and group of a file
# Equivalent to stdlib's `mog`, defined locally so that this policy file is
# self contained and does not clash with the standard library.
{
        mode   => "$(mode)";
        owners => { "$(user)" };
        groups => { "$(group)" };
        rxdirs => "false";
}

bundle agent __main__
# @brief Allow this policy to be run directly: cf-agent -KIf ./motd.cf
{
  methods:
      "motd";
}
```

## `def.json`

```json
{
  "variables": {
    "motd_banner": "*** ACME Inc. - Authorized use only ***",
    "motd_message": [
      "All activity on this system is logged and monitored.",
      "Disconnect immediately if you are not an authorized user.",
      "",
      "Host: $(sys.fqhost)   Policy server: $(sys.policy_hub)"
    ],
    "motd_footer": "Questions? Contact admin@example.com"
  }
}
```

## Notes

- **The three independent knobs** are `motd_banner` (string), `motd_message` (list of lines), and `motd_footer` (string). Each is guarded by its own `isvariable()` pair, so you can set one, two, or all three in `def.json`; whatever you leave out keeps its in-policy default. Variables from augments land in the `default:def` namespace, hence the fully qualified references.
- `motd_message` must be a **list** in augments (it's expanded with `@()`); the other two are strings. Augments values are expanded, so `$(sys.fqhost)` and friends work inside them, as the test output shows.
- The file path is a plain policy variable (`/etc/motd`) rather than a fourth augments setting, since the request was for three variables driving the content. Promote it the same way if you want it host-configurable.
- **Integration:** drop `motd.cf` in `services/` (or wherever you keep policy), add it to `inputs`, and call `usebundle => motd` from a methods promise in `bundle agent main`/`services_autorun`. Put the `variables` keys into your real `$(sys.masterdir)/def.json` — the shipped one here is an example.
- **Testing:** `cf-agent -KIf ./motd.cf` runs it standalone via the `__main__` bundle and picks up `./def.json` from the same directory. Requires CFEngine 3.18+ for the `content` attribute; verified against 3.27.1.