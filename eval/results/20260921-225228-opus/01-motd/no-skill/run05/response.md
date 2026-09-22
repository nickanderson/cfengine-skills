Three files written to the working directory, syntax-checked with `cf-promises` 3.27.1 and functionally tested with `cf-agent` (full augments, no augments, and partial augments — plus a convergence re-run that made no changes).

One note on implementation: `default()` is not available as a function in this CFEngine build, so the augment overrides are done with `isvariable()` class guards. This has the same effect and avoids the unresolved-argument problem you'd hit with `ifelse()` when a variable isn't defined at all.

## `motd.cf`

```cfengine3
bundle agent motd
# @brief Manage the content of the message of the day
#
# The rendered file is assembled from three independent variables. Each one
# can be overridden from augments (def.json) without editing policy:
#
#   default:def.motd_banner  - greeting shown at the top of the file
#   default:def.motd_contact - who is responsible for this host
#   default:def.motd_legal   - legal / acceptable use notice
#
# Any variable left unset in augments falls back to the default defined in
# this bundle, so the policy is safe to run with no augments at all.
{
  classes:

      "have_motd_banner"
        expression => isvariable( "def.motd_banner" ),
        comment    => "The banner has been defined in augments";

      "have_motd_contact"
        expression => isvariable( "def.motd_contact" ),
        comment    => "The contact has been defined in augments";

      "have_motd_legal"
        expression => isvariable( "def.motd_legal" ),
        comment    => "The legal notice has been defined in augments";

  vars:

      # 1st independent variable: the greeting

    have_motd_banner::
      "banner" string => "$(def.motd_banner)";

    !have_motd_banner::
      "banner" string => "Welcome to $(sys.fqhost)";

      # 2nd independent variable: ownership / contact information

    have_motd_contact::
      "contact" string => "$(def.motd_contact)";

    !have_motd_contact::
      "contact" string => "Contact your system administrator before making changes.";

      # 3rd independent variable: legal notice

    have_motd_legal::
      "legal" string => "$(def.motd_legal)";

    !have_motd_legal::
      "legal" string => "Unauthorized access is prohibited. All activity may be monitored and reported.";

    any::

      "path"
        string  => "/etc/motd",
        comment => "Location of the message of the day";

      "content"
        string  => "$(banner)$(const.n)$(const.n)$(contact)$(const.n)$(const.n)$(legal)$(const.n)",
        comment => "The fully rendered message of the day";

  files:

      "$(path)"
        create  => "true",
        content => "$(content)",
        perms   => mog( "0644", "root", "root" ),
        classes => results( "bundle", "motd" ),
        comment => "The message of the day should present the banner, contact
                    and legal information defined by policy so that every host
                    greets its users with a consistent and correct message.";

  reports:

    motd_repaired::
      "Updated '$(path)'";

    motd_failed|motd_denied|motd_timeout::
      "Unable to update '$(path)'";

    inform_mode::
      "$(this.bundle): banner  = '$(banner)'";
      "$(this.bundle): contact = '$(contact)'";
      "$(this.bundle): legal   = '$(legal)'";
}
```

## `def.json`

```json
{
  "variables": {
    "default:def.motd_banner": "Welcome to $(sys.fqhost) - managed by CFEngine",
    "default:def.motd_contact": "Owner: Operations Team <ops@example.com>",
    "default:def.motd_legal": "This system is for authorized use only. All activity may be monitored and reported."
  }
}
```

Each key is optional and independent — drop any of the three and that line falls back to the policy default.

## `promises.cf`

Standalone entry point, so the example runs on its own with `cf-agent --no-lock --inform --file ./promises.cf`. If you are dropping `motd.cf` into an existing policy set, skip this file and add `motd.cf` to your `inputs` and `motd` to the relevant bundlesequence/methods instead.

```cfengine3
body common control
# @brief Standalone entry so the example can be run directly:
#        cf-agent --no-lock --inform --file ./promises.cf
{
      inputs => { "$(sys.libdir)/stdlib.cf", "motd.cf" };
      bundlesequence => { "main" };
}

bundle agent main
{
  methods:

      "motd"
        usebundle => motd;
}
```

Rendered result with the augments above:

```
Welcome to <host> - managed by CFEngine

Owner: Operations Team <ops@example.com>

This system is for authorized use only. All activity may be monitored and reported.
```

`mog()` and `results()` come from stdlib, which `promises.cf` pulls in via `$(sys.libdir)/stdlib.cf`.