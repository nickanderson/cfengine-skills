Policy validates cleanly (exit 0, no errors — the earlier DMI messages were just sandbox permission noise from hardware inventory detection, unrelated to this policy).

## Summary

Three files in the working directory:

- **`motd.cf`** — the policy library, defining `bundle agent motd` with three `policy => "overridable"` variables (so they're augment-configurable) and the file-editing logic.
- **`promises.cf`** — the entry point (`body common control` with bundlesequence/inputs).
- **`def.json`** — example augments overriding all three variables.

The three variables:
1. `motd.motd_message` — the greeting/banner text
2. `motd.motd_show_sysinfo` — `"true"`/`"false"`, whether to append a hostname/OS/kernel line
3. `motd.motd_file` — path of the file to manage (defaults to `/etc/motd`, could be pointed at `/etc/motd.tail` etc.)

```cfengine3
##############################################################################
# motd.cf - manage the system's message of the day (/etc/motd by default)
#
# Three independent, augments-configurable variables control the content:
#   motd.motd_message        - the greeting/banner text shown at the top
#   motd.motd_show_sysinfo   - "true"/"false", whether to append system info
#   motd.motd_file           - the path of the file to manage
#
# All three are declared with policy => "overridable" so that a def.json
# augments file can override their default values without editing this file.
##############################################################################

bundle agent motd
{
  vars:
      "motd_message"
        string => "Welcome to $(sys.host). Authorized users only.",
        policy => "overridable",
        comment => "Greeting/banner text placed at the top of the motd file";

      "motd_show_sysinfo"
        string => "true",
        policy => "overridable",
        comment => "'true' to append hostname/OS/kernel info below the greeting, 'false' to omit it";

      "motd_file"
        string => "/etc/motd",
        policy => "overridable",
        comment => "Full path of the file CFEngine manages as the message of the day";

  files:
      "$(motd_file)"
        create        => "true",
        edit_line     => build_motd,
        edit_defaults => motd_edit_defaults,
        perms         => motd_perms,
        classes       => if_repaired("motd_updated");

  reports:
    motd_updated::
      "Updated motd content in $(motd_file)";
}

##############################################################################
# Builds the actual file content based on motd.motd_message and
# motd.motd_show_sysinfo. Kept self-contained (reads motd.* vars directly)
# so it does not depend on cross-bundle class scoping rules.
##############################################################################
bundle edit_line build_motd
{
  vars:
      "show_sysinfo" string => "$(motd.motd_show_sysinfo)";

  classes:
      "do_sysinfo" expression => strcmp("$(show_sysinfo)", "true");

  insert_lines:
      "$(motd.motd_message)"
        location => start;

      "System: $(sys.fqhost)  OS: $(sys.os) $(sys.release)  Arch: $(sys.arch)"
        ifvarclass => "do_sysinfo";
}

##############################################################################
# Supporting bodies (kept local so this policy has no external dependencies)
##############################################################################
body edit_defaults motd_edit_defaults
{
      empty_file_before_editing => "true";
      max_file_size             => "50000";
}

body perms motd_perms
{
      mode  => "644";
      owner => "root";
      group => "root";
}

body classes if_repaired(x)
{
      promise_repaired => { "$(x)" };
}
```

```cfengine3
body common control
{
      bundlesequence => { "motd" };
      inputs         => { "motd.cf" };
}
```

```json
{
    "variables": {
        "default:motd.motd_message": {
            "value": "Welcome to ACME Corp - authorized access only. All activity is monitored.",
            "comment": "Overrides the default greeting shown at the top of /etc/motd"
        },
        "default:motd.motd_show_sysinfo": {
            "value": "true",
            "comment": "Set to false to hide the hostname/OS/kernel info line"
        },
        "default:motd.motd_file": {
            "value": "/etc/motd",
            "comment": "Change if this platform uses a different motd path, e.g. /etc/motd.tail"
        }
    }
}
```

Notes/assumptions:
- `def.json` is auto-loaded by `cf-agent` when placed next to `promises.cf`, so no explicit wiring is needed beyond dropping it in the policy directory.
- The file is emptied and rebuilt each run (`empty_file_before_editing`) so changing `motd_message` doesn't leave stale lines behind.
- Perms/classes bodies are defined locally rather than pulled from the CFEngine standard library, so this policy has no external dependencies and runs standalone.