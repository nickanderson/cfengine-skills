Wrote three files and validated them against CFEngine 3.27.1: syntax passes, the policy renders correctly both with and without augments, and a repeat run is a no-op (converged).

One note on the approach: `default()` is not a function in this CFEngine build, so the augments-or-fallback logic uses `isvariable()` classes instead. That keeps the fallback branch from ever referencing an undefined variable.

## `motd.cf`

```cfengine3
bundle agent motd
# @brief Manage the content of the message of the day (/etc/motd)
#
# Three independent variables drive the rendered content. Each one can be
# overridden from augments (def.json) without editing this policy:
#
#   default:def.motd_banner       - greeting shown at the top
#   default:def.motd_environment  - environment/classification label
#   default:def.motd_contact      - who to contact about this host
#
# Example def.json:
#
#   {
#     "variables": {
#       "motd_banner":      "*** ACME Production Host ***",
#       "motd_environment": "production",
#       "motd_contact":     "ops@example.com"
#     }
#   }
#
# When a variable is not supplied by augments the policy falls back to a
# sensible default, so the policy is useful with no augments at all.
{
  vars:

      # --- The three independent, augments-configurable variables ----------

    motd_banner_from_augments::
      "banner"      string => "$(default:def.motd_banner)",
                    comment => "Greeting line, supplied by augments";

    !motd_banner_from_augments::
      "banner"      string => "Welcome to $(sys.fqhost)",
                    comment => "Greeting line, policy default";

    motd_environment_from_augments::
      "environment" string => "$(default:def.motd_environment)",
                    comment => "Environment label, supplied by augments";

    !motd_environment_from_augments::
      "environment" string => "unclassified",
                    comment => "Environment label, policy default";

    motd_contact_from_augments::
      "contact"     string => "$(default:def.motd_contact)",
                    comment => "Point of contact, supplied by augments";

    !motd_contact_from_augments::
      "contact"     string => "root@$(sys.fqhost)",
                    comment => "Point of contact, policy default";

      # --- Rendering -------------------------------------------------------

    any::
      "path"
        string  => "/etc/motd",
        comment => "Location of the message of the day";

      "lines"
        slist   => {
                     "$(banner)",
                     "",
                     "  Host:        $(sys.fqhost)",
                     "  Environment: $(environment)",
                     "  Contact:     $(contact)",
                     "",
                     "  This system is managed by CFEngine.",
                     "  Local modifications to $(path) will be reverted.",
                   },
        comment => "The message of the day, one list entry per rendered line";

      "content"
        string  => format( "%s%s", join( "$(const.n)", "lines" ), "$(const.n)" ),
        comment => "Rendered message of the day, newline terminated";

  classes:

      "motd_banner_from_augments"
        expression => isvariable( "default:def.motd_banner" ),
        scope      => "bundle",
        comment    => "True when augments supplies the banner";

      "motd_environment_from_augments"
        expression => isvariable( "default:def.motd_environment" ),
        scope      => "bundle",
        comment    => "True when augments supplies the environment label";

      "motd_contact_from_augments"
        expression => isvariable( "default:def.motd_contact" ),
        scope      => "bundle",
        comment    => "True when augments supplies the contact";

  files:

      "$(path)"
        create  => "true",
        content => "$(content)",
        perms   => mog( "0644", "root", "root" ),
        comment => "Keep the message of the day consistent with policy",
        handle  => "motd_files_content";

  reports:

    verbose_mode::
      "Rendering $(path) with banner='$(banner)' environment='$(environment)' contact='$(contact)'";
}
```

## `def.json` (augments)

```json
{
  "variables": {
    "motd_banner":      "*** Northern.tech managed system ***",
    "motd_environment": "production",
    "motd_contact":     "admin@example.com"
  }
}
```

## `promises.cf` (standalone test driver)

```cfengine3
# Standalone driver so the policy can be tested with:
#
#   cf-agent -KIf ./promises.cf
#
# def.json in this directory is loaded automatically as augments.
# When adding motd.cf to masterfiles instead, drop this file, list
# motd.cf in your inputs and add 'motd' to your bundlesequence -
# stdlib is already loaded there.

body file control
{
      inputs => { "$(sys.libdir)/stdlib.cf", "motd.cf" };
}

body common control
{
      bundlesequence => { "motd" };
}
```

### Verification performed
- `cf-promises -f ./promises.cf` — clean.
- Run with no `def.json`: rendered the three fallbacks (`Welcome to <fqhost>`, `unclassified`, `root@<fqhost>`).
- Run with `def.json`: all three augments values took effect in the output.
- Third run: no output, no repair — convergent.

Tests ran against a temporary path since the sandbox isn't root; the shipped policy targets `/etc/motd` with `mog("0644","root","root")`. `content` on `files` requires CFEngine 3.18 or newer. To override just one variable, put only that key in `def.json` — the other two keep their defaults independently.