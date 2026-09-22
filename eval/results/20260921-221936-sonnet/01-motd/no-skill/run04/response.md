The policy is validated and working as intended. Here are the final files:

**`motd.cf`**
```cfengine3
#######################################################
#
# motd.cf - Manage the Message of the Day (/etc/motd)
#
# Three independent variables control this policy, each of which can
# be overridden by site-specific augments (def.json) without editing
# this file:
#
#   def.motd_path    - full path to the motd file      (default: /etc/motd)
#   def.motd_message - the content written to the file (default: see below)
#   def.motd_mode    - octal permission mode            (default: "644")
#
# Example def.json overriding all three:
#
#   {
#     "variables": {
#       "default:def.motd_path":    { "value": "/etc/motd" },
#       "default:def.motd_message": { "value": "Welcome!\nAuthorized users only." },
#       "default:def.motd_mode":    { "value": "0644" }
#     }
#   }
#
#######################################################

body common control
{
      bundlesequence => { "motd" };
}

#######################################################

bundle agent motd
{
  vars:
      # --- motd_path -------------------------------------------------
      "path"
        string => "$(def.motd_path)",
        if      => isvariable("def.motd_path"),
        comment => "Path to the motd file. Configurable via augments as def.motd_path.";

      "path"
        string  => "/etc/motd",
        unless  => isvariable("def.motd_path"),
        comment => "Default path to the motd file.";

      # --- motd_message ------------------------------------------------
      "message"
        string => "$(def.motd_message)",
        if      => isvariable("def.motd_message"),
        comment => "Content of the motd file. Configurable via augments as def.motd_message.";

      "message"
        string  => "Welcome to $(sys.fqhost)!
Authorized users only. All activity may be monitored and reported.",
        unless  => isvariable("def.motd_message"),
        comment => "Default motd content.";

      # --- motd_mode -------------------------------------------------
      "mode"
        string => "$(def.motd_mode)",
        if      => isvariable("def.motd_mode"),
        comment => "Permission mode for the motd file. Configurable via augments as def.motd_mode.";

      "mode"
        string  => "644",
        unless  => isvariable("def.motd_mode"),
        comment => "Default permission mode for the motd file.";

      "lines"
        slist => splitstring("$(motd.message)", "\n", "1000"),
        comment => "Configured motd content split into lines for edit_line.";

  files:
      "$(motd.path)"
        create        => "true",
        perms         => motd_perms("$(motd.mode)", "root", "root"),
        edit_line     => motd_set_content("@(motd.lines)"),
        edit_defaults => motd_empty_file,
        classes       => motd_results("motd_updated"),
        comment       => "Ensure the motd file matches the configured content, mode and ownership.";

  reports:
    motd_updated_repaired::
      "$(this.bundle): updated $(motd.path) (mode $(motd.mode))";
}

#######################################################

bundle edit_line motd_set_content(content)
{
  insert_lines:
      "$(content)"
        comment => "Insert the configured motd content.";
}

#######################################################

body edit_defaults motd_empty_file
{
      empty_file_before_editing => "true";
      max_file_size             => "1M";
}

body perms motd_perms(m, o, g)
{
      mode   => "$(m)";
      owners => { "$(o)" };
      groups => { "$(g)" };
}

body classes motd_results(x)
{
      promise_repaired => { "$(x)_repaired" };
      repair_failed    => { "$(x)_failed" };
}
```

**`def.json`**
```json
{
  "variables": {
    "default:def.motd_path": {
      "value": "/etc/motd",
      "comment": "Path to the file managed by bundle agent motd"
    },
    "default:def.motd_message": {
      "value": "Welcome to this system!\nAuthorized users only. All activity may be monitored and reported.",
      "comment": "Content written to the motd file, newline-separated"
    },
    "default:def.motd_mode": {
      "value": "0644",
      "comment": "Permission mode applied to the motd file"
    }
  }
}
```

Notes:
- The three independent, augment-configurable variables are `motd_path`, `motd_message`, and `motd_mode`. Each falls back to a sane built-in default (`/etc/motd`, a generic banner, `644`) via `isvariable("def.*")` checks if `def.json` doesn't define it — verified both with and without `def.json` present using `cf-promises --show-vars`.
- `motd_message` accepts embedded `\n` for multi-line content; the policy splits it into lines and fully rewrites the file each run (`empty_file_before_editing`) so it converges exactly to the configured content rather than just appending.
- Ownership is fixed to `root:root`; only mode is exposed as a variable, since that's the attribute admins typically need to tune (e.g. `0644` vs `0444`). Adjust the `motd_perms` body if per-site owner/group also needs to be configurable.
- Validated with `cf-promises` (installed CFEngine Core/Enterprise 3.27.1) — syntax check passes and `--show-vars` confirms augment overrides and fallback defaults both resolve correctly.