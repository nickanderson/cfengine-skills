I've written a self-contained CFEngine policy for MOTD management with three augment-configurable variables.

## `motd.cf`

```cfengine3
###############################################################################
# motd.cf - Manage the message of the day (/etc/motd)
#
# Three independent variables control the rendered content. Each has a
# built-in default but can be overridden per-host/per-group via augments
# (def.json) without touching this policy file:
#
#   def.motd_message       - main greeting/banner text (top of the file)
#   def.motd_show_sysinfo  - "true"/"false", whether to append a system
#                             info block (hostname, OS, IP)
#   def.motd_footer        - footer/contact line (bottom of the file)
#
# See def.json in this directory for an example override file. Augments
# placed at the root of your masterfiles (as def.json, or merged in via
# "augments =>" in body common control) are automatically available as
# variables in the special "def" bundle, e.g. $(def.motd_message).
###############################################################################

body common control
{
      bundlesequence => { "motd" };
}

bundle agent motd
{
  vars:
      "message"
        string => ifelse(isvariable("def.motd_message"), "$(def.motd_message)",
                          "Welcome to $(sys.fqhost)"),
        comment => "Main MOTD greeting. Override via def.json: def.motd_message";

      "show_sysinfo"
        string => ifelse(isvariable("def.motd_show_sysinfo"), "$(def.motd_show_sysinfo)",
                          "true"),
        comment => "Whether to append a system info block ('true'/'false'). Override via def.json: def.motd_show_sysinfo";

      "footer"
        string => ifelse(isvariable("def.motd_footer"), "$(def.motd_footer)",
                          "This system is managed by CFEngine."),
        comment => "Footer line appended to the MOTD. Override via def.json: def.motd_footer";

  classes:
      "show_sysinfo_enabled"
        expression => strcmp("$(show_sysinfo)", "true"),
        comment => "True when the system info block should be rendered";

  files:
      "/etc/motd"
        create        => "true",
        edit_line     => motd_content,
        edit_defaults => motd_reset,
        classes       => motd_if_repaired("motd_updated"),
        comment       => "Rebuild /etc/motd from the motd_message/motd_show_sysinfo/motd_footer variables";

  reports:
    "motd_updated"::
      "$(this.bundle): /etc/motd was rebuilt on $(sys.fqhost)";
}

bundle edit_line motd_content
{
  insert_lines:
      "$(motd.message)"
        comment => "Main greeting";

      ""
        comment => "Blank line separator before optional system info block";

      "System information:"
        ifvarclass => "show_sysinfo_enabled",
        comment    => "Header for the optional system info block";

      "  Hostname: $(sys.fqhost)"
        ifvarclass => "show_sysinfo_enabled";

      "  Operating system: $(sys.flavor)"
        ifvarclass => "show_sysinfo_enabled";

      "  IP address: $(sys.ipv4)"
        ifvarclass => "show_sysinfo_enabled";

      ""
        comment => "Blank line separator before footer";

      "$(motd.footer)"
        comment => "Footer line";
}

body edit_defaults motd_reset
{
      empty_file_before_editing => "true";
      max_file_size             => "10k";
}

body classes motd_if_repaired(x)
{
      promise_repaired => { "$(x)" };
}
```

## `def.json` (example augments)

```json
{
  "variables": {
    "def.motd_message": {
      "value": "Welcome to ACME Corp. Authorized users only.",
      "comment": "Main greeting shown at the top of /etc/motd"
    },
    "def.motd_show_sysinfo": {
      "value": "true",
      "comment": "Set to \"false\" to omit the hostname/OS/IP block"
    },
    "def.motd_footer": {
      "value": "Contact: admin@example.com | Managed by CFEngine",
      "comment": "Footer line shown at the bottom of /etc/motd"
    }
  }
}
```

### How it works

- `motd.message`, `motd.show_sysinfo`, `motd.footer` are the three independent variables. Each uses `ifelse(isvariable("def.X"), "$(def.X)", <built-in default>)` — the standard CFEngine idiom for augment-overridable defaults, so the policy works unmodified even with no `def.json` present.
- `/etc/motd` is fully cleared (`empty_file_before_editing`) and rebuilt each run, so toggling `motd_show_sysinfo` cleanly adds/removes that block rather than leaving stale lines.
- Drop `def.json` next to your masterfiles (or merge it via `augments =>` in your existing `body common control`) to override any of the three values per-host or per-group without editing `motd.cf`.
- Test standalone with `cf-agent -KIf motd.cf` from this directory (place `def.json` alongside it, or in the policy's `inputs` search path, so it gets merged).