The end-to-end test succeeded — the file was created with the correct content, the augment-supplied path was honored, and the unoverridden `message` fell back to its built-in default. (The `chown` error is only because the test ran as a non-root user trying to set owner `root`; that's expected in this sandbox, not a policy defect.)

## Summary

The policy lives in `/tmp/cfeval-01-motd-no-skill.gudVCobF/work/`: `promises.cf` (entry point), `motd.cf` (the bundle), and `def.json` (example augment overrides). It manages `/etc/motd` and exposes three independently configurable variables — `message`, `path`, and `mode` — each overridable via `def.json` using the `unless => isvariable(...)` guard, which I verified empirically is necessary (a plain `vars:` promise silently overwrites augment values, since CFEngine evaluates `vars` across the whole bundlesequence before any `classes`).

```cf3
# promises.cf
body common control
{
      bundlesequence => { "motd" };
      inputs         => { "motd.cf" };
}
```

```cf3
# motd.cf
# Manage the contents, location and permissions of the message-of-the-day
# file.
#
# Three variables control this policy, all overridable via augments
# (def.json) without editing this file:
#
#   default:motd.message  - text written into the MOTD file (may span
#                            multiple lines using literal "\n")
#   default:motd.path     - path to the MOTD file to manage
#   default:motd.mode     - permission mode applied to the MOTD file
#
# Example def.json:
# {
#   "vars": {
#     "default:motd.message": "Welcome to ACME Corp.\nAuthorized use only.",
#     "default:motd.path": "/etc/motd",
#     "default:motd.mode": "0644"
#   }
# }

bundle agent motd
{
  vars:
      # "unless => isvariable(...)" is evaluated in place while this
      # promise is processed, so it correctly detects a value already
      # installed by an augment (def.json is loaded before any promise
      # evaluation begins) and skips setting the built-in default in
      # that case. A plain, unconditional "vars" promise would instead
      # unconditionally overwrite whatever the augment provided.
      "message"
        string => "This system is managed by CFEngine.",
        unless  => isvariable("motd.message"),
        comment => "Content written to the MOTD file; overridable via def.json";

      "path"
        string => "/etc/motd",
        unless  => isvariable("motd.path"),
        comment => "Location of the MOTD file; overridable via def.json";

      "mode"
        string => "0644",
        unless  => isvariable("motd.mode"),
        comment => "Permission mode of the MOTD file; overridable via def.json";

  files:
      "$(motd.path)"
        create        => "true",
        edit_line     => motd_content("$(motd.message)"),
        edit_defaults => motd_edit_defaults,
        perms         => motd_perms("$(motd.mode)"),
        classes       => motd_results("motd"),
        comment       => "Ensure the MOTD file matches the configured content, path and mode";

  reports:
    motd_repaired::
      "$(this.bundle): $(motd.path) was updated";
    motd_failed::
      "$(this.bundle): failed to update $(motd.path)";
}

bundle edit_line motd_content(text)
{
  vars:
      "as_list" slist => splitstring("$(text)", "\n", "1000");

  insert_lines:
      "$(as_list)";
}

body edit_defaults motd_edit_defaults
{
      empty_file_before_editing => "true";
      edit_backup               => "false";
}

body perms motd_perms(mode)
{
      mode   => "$(mode)";
      owners => { "root" };
      groups => { "root" };
}

body classes motd_results(prefix)
{
      promise_repaired => { "$(prefix)_repaired" };
      repair_failed     => { "$(prefix)_failed" };
}
```

```json
// def.json
{
  "vars": {
    "default:motd.message": "Welcome to ACME Corp.\nUnauthorized access to this system is prohibited.",
    "default:motd.path": "/etc/motd",
    "default:motd.mode": "0644"
  }
}
```

Validated with `cf-promises`/`cf-agent --dry-run` and a real (non-root) write test: augment values correctly override in-policy defaults, unoverridden variables fall back correctly, and the file content/mode are applied as expected.