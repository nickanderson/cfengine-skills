Both files are in place and the policy has been verified end-to-end with `cf-agent` (syntax check, augment overrides for all three variables, and fallback to built-in defaults when `def.json` is absent).

## `motd.cf`

```cf3
#####################################################################
# motd.cf
#
# Manages the "message of the day" file. Exposes three independent
# variables (content, target file, permissions mode) in the special
# "def" common bundle, each with a built-in default that is used
# only if not already supplied by augments (def.json). This is the
# standard CFEngine idiom for augment-overridable variables: the
# "unless => isvariable(...)" guard means a value already installed
# by def.json wins, since augments load before policy is evaluated
# and policy is only allowed to fill in the gaps.
#
# Override any of these from def.json, e.g.:
#   { "vars": { "motd_message": "...", "motd_file": "...", "motd_mode": "..." } }
#####################################################################

bundle common def
{
  vars:
      "motd_message"
        string => "Welcome to $(sys.host).
This system is for authorized use only.
All activity may be monitored and reported.",
        unless  => isvariable("motd_message"),
        comment => "MOTD text content. Override via augments: default:def.motd_message";

      "motd_file"
        string  => "/etc/motd",
        unless  => isvariable("motd_file"),
        comment => "Path to the MOTD file. Override via augments: default:def.motd_file";

      "motd_mode"
        string  => "644",
        unless  => isvariable("motd_mode"),
        comment => "Permissions (octal) for the MOTD file. Override via augments: default:def.motd_mode";
}

bundle agent motd
{
  files:
      "$(def.motd_file)"
        create        => "true",
        perms         => motd_perms("$(def.motd_mode)"),
        edit_line     => motd_set_content("$(def.motd_message)"),
        edit_defaults => motd_empty_before_edit,
        classes       => motd_if_repaired("motd_content_updated");

  reports:
    motd_content_updated::
      "$(this.bundle): updated MOTD content at $(def.motd_file)";
}

bundle edit_line motd_set_content(content)
{
  insert_lines:
      "$(content)"
        comment => "Insert the configured MOTD content, replacing prior content";
}

body perms motd_perms(mode)
{
      mode   => "$(mode)";
      owners => { "root" };
      groups => { "root" };
}

body edit_defaults motd_empty_before_edit
{
      empty_file_before_editing => "true";
      max_file_size             => "1M";
}

body classes motd_if_repaired(x)
{
      promise_repaired => { "$(x)" };
}

#####################################################################
# Standalone entry point so this file can be run directly with:
#   cf-agent -KIf motd.cf
# When included into a larger policy set via inputs, this body can
# be omitted / merged with the existing body common control.
#####################################################################
body common control
{
      bundlesequence => { "motd" };
}
```

## `def.json`

```json
{
  "vars": {
    "motd_message": "Welcome to ACME Corp.\nThis system is for authorized use only.\nAll activity is monitored and logged.",
    "motd_file": "/etc/motd",
    "motd_mode": "644"
  }
}
```

Notes on the design:

- The three variables — `motd_message`, `motd_file`, `motd_mode` — live in `bundle common def`, which is CFEngine's conventional home for augment-tunable defaults (variables there are globally visible as `$(def.varname)`).
- Each uses `unless => isvariable(...)`, so if `def.json` already supplied the value (augments load before policy is parsed/evaluated), the built-in default is skipped — that's the only pattern that actually lets augments win, since a plain `vars:` promise for the same name in policy would otherwise clobber the augment value.
- `def.json` targets these via the `vars` key, which by default binds to `default:def.<name>`.
- I verified with `cf-agent`: overriding all three (custom message, custom path, mode `640`) produced the exact expected file at the custom path with 640 permissions and the custom content inserted line-by-line; removing `def.json` entirely falls back cleanly to `/etc/motd`, mode `644`, and the built-in banner text.