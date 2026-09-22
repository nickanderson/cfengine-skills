The final policy is in `motd.cf`, `promises.cf`, and `def.json` in the working directory, validated with `cf-promises`/`cf-agent` 3.27.1.

## Design

- `bundle common motd_def` declares three independent, augment-configurable variables — `header`, `message`, `footer` — each guarded with `unless => isvariable(...)` so a value supplied by `def.json` always wins over the in-policy fallback (the documented CFEngine idiom for augment-overridable defaults).
- `bundle agent motd` concatenates the three into an ordered list and uses `edit_line` with `empty_file_before_editing` so the target file's content is fully convergent (exact 3 lines, drift corrected on every run) rather than just appended-to.
- `path` is a plain internal default (`/etc/motd`), intentionally not augment-driven, keeping exactly 3 configurable variables as requested.

Verified: augments override `header`/`message`/`footer` (confirmed via `cf-promises --show-vars`, `source=augments_file`), the assembled file matches exactly the 3 lines in order, and it's idempotent/self-healing (a tampered line was removed and the correct content restored on the next run).

**motd.cf**
```cfengine3
bundle common motd_def
# @brief Fallback values for the three motd content variables. Each is
# only set here if not already provided by site policy via augments
# (def.json); otherwise the augmented value takes precedence:
#
#   { "vars": { "default:motd_def.header": "..." } }
{
  vars:
      "path"
        string => "/etc/motd",
        comment => "Path to the file managed as the message of the day.";

      "header"
        string => "*** Welcome to $(sys.host) ***",
        unless => isvariable("motd_def.header"),
        comment => "Header/banner line shown at the top of the motd.
                     Configurable via augments as default:motd_def.header.";

      "message"
        string => "Authorized users only. All activity may be monitored and reported.",
        unless => isvariable("motd_def.message"),
        comment => "Main body text of the motd.
                     Configurable via augments as default:motd_def.message.";

      "footer"
        string => "Managed by CFEngine - do not edit directly.",
        unless => isvariable("motd_def.footer"),
        comment => "Footer line shown at the bottom of the motd.
                     Configurable via augments as default:motd_def.footer.";
}

bundle agent motd
# @brief Assemble motd_def's header, message and footer into
# $(motd_def.path) and keep it in that exact state.
{
  vars:
      "content"
        slist => { "$(motd_def.header)", "$(motd_def.message)", "$(motd_def.footer)" },
        comment => "Ordered lines written to $(motd_def.path), assembled
                     from the three independent motd_def variables.";

  files:
      "$(motd_def.path)"
        create        => "true",
        edit_line     => motd_set_lines(@(content)),
        edit_defaults => motd_empty_before_edit,
        perms         => motd_perms("644", "root", "root"),
        classes       => motd_if_repaired("motd_updated");

  reports:
    motd_updated.(inform_mode|verbose_mode)::
      "Updated $(motd_def.path) with the current motd content";
}

bundle edit_line motd_set_lines(lines)
# @brief Replace the file content with exactly the given lines, in order.
{
  vars:
      "want" slist => { @(lines) };

  insert_lines:
      "$(want)"
        insert_type => "preserve_all_lines";
}

body edit_defaults motd_empty_before_edit
{
      empty_file_before_editing => "true";
}

body perms motd_perms(mode, owner, group)
{
      mode   => "$(mode)";
      owners => { "$(owner)" };
      groups => { "$(group)" };
}

body classes motd_if_repaired(x)
{
      promise_repaired => { "$(x)" };
}
```

**promises.cf**
```cfengine3
body common control
{
      bundlesequence => { "motd" };
      inputs         => { "motd.cf" };
}
```

**def.json** (example augments — place alongside `promises.cf`; CFEngine auto-loads it)
```json
{
  "vars": {
    "default:motd_def.header": "*** Welcome to $(sys.host) ***",
    "default:motd_def.message": "Authorized users only. All activity may be monitored and reported.",
    "default:motd_def.footer": "Managed by CFEngine - do not edit directly."
  }
}
```