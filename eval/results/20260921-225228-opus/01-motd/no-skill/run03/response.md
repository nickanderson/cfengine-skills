Written to `/tmp/cfeval-01-motd-no-skill.tjPfANG6/work/` and verified against CFEngine 3.27.1 (`cf-promises` clean; `cf-agent` run renders correctly with and without augments, and is convergent on a second run).

**The three variables**, each independently overridable from `def.json`:

| Augments key | Type | Default when unset |
|---|---|---|
| `motd_header` | string | `Welcome to $(sys.fqhost) ($(sys.flavour) $(sys.arch))` |
| `motd_body` | slist | two generic "managed by CFEngine" lines |
| `motd_contact` | string | `root@$(sys.fqhost)` |

Each is a paired `vars` promise guarded by `if => isvariable(...)` / `not(isvariable(...))`, so an unset key falls back to a sane built-in rather than leaving an unresolved variable in the file. (I deliberately avoided the `classes:`-plus-context idiom here: `vars` are evaluated before `classes` within a pass, so the default would win on the first pass.)

### `promises.cf`
```cfengine3
body common control
{
      bundlesequence => { "motd" };
      inputs         => { "$(sys.libdir)/stdlib.cf", "motd.cf" };
}
```

### `motd.cf`
```cfengine3
bundle agent motd
# @brief Manage the message of the day (/etc/motd)
#
# The content is built from three independent variables, each of which can be
# overridden from augments (def.json) without editing this policy:
#
#   default:def.motd_header   string  Headline shown at the top of the motd
#   default:def.motd_body     slist   Body lines, rendered one per line
#   default:def.motd_contact  string  Support contact shown in the footer
#
# Example def.json:
#
#   {
#     "variables": {
#       "motd_header": "ACME Production - authorized use only",
#       "motd_body": [ "Patched weekly, Sundays 02:00 UTC.", "Tickets: https://jira.example.com" ],
#       "motd_contact": "ops@example.com"
#     }
#   }
{
  vars:
      # 1. Header ---------------------------------------------------------
      "header"
        string => "$(default:def.motd_header)",
        if     => isvariable("default:def.motd_header"),
        comment => "Use the header supplied by augments";

      "header"
        string => "Welcome to $(sys.fqhost) ($(sys.flavour) $(sys.arch))",
        if     => not(isvariable("default:def.motd_header")),
        comment => "Fall back to a generated header";

      # 2. Body -----------------------------------------------------------
      "body"
        slist  => { @(default:def.motd_body) },
        if     => isvariable("default:def.motd_body"),
        comment => "Use the body lines supplied by augments";

      "body"
        slist  => { "This system is managed by CFEngine.",
                    "Local changes may be reverted automatically." },
        if     => not(isvariable("default:def.motd_body")),
        comment => "Fall back to a generic body";

      # 3. Contact --------------------------------------------------------
      "contact"
        string => "$(default:def.motd_contact)",
        if     => isvariable("default:def.motd_contact"),
        comment => "Use the contact address supplied by augments";

      "contact"
        string => "root@$(sys.fqhost)",
        if     => not(isvariable("default:def.motd_contact")),
        comment => "Fall back to the local root alias";

      # Render the three variables into the template data -----------------
      "template_data"
        data => mergedata('{ "header": "$(header)", "contact": "$(contact)", "body": body }');

      "template"
        string => "$(this.promise_dirname)/templates/motd.mustache";

      "motd_file"
        string => "/etc/motd";

  files:
      "$(motd_file)"
        create        => "true",
        template_method => "mustache",
        edit_template => "$(template)",
        template_data => @(template_data),
        perms         => mog("0644", "root", "root"),
        classes       => results("bundle", "motd_file"),
        comment       => "The motd is the first thing an operator sees; it must identify the host and who to contact about it.";

  reports:
    motd_file_repaired::
      "$(this.bundle): updated $(motd_file)";

    inform_mode::
      "$(this.bundle): header  = '$(header)'";
      "$(this.bundle): body    = '$(body)'";
      "$(this.bundle): contact = '$(contact)'";
}
```

### `templates/motd.mustache`
```mustache
{{{header}}}

{{#body}}
  {{{.}}}
{{/body}}

Contact: {{{contact}}}
```

### `def.json` (example augments)
```json
{
  "variables": {
    "motd_header": "*** ACME Corp - Production - Authorized Use Only ***",
    "motd_body": [
      "Host $(sys.fqhost) is managed by CFEngine; local edits may be reverted.",
      "Patch window: Sundays 02:00-04:00 UTC.",
      "All sessions are logged."
    ],
    "motd_contact": "ops@example.com"
  }
}
```

Rendered output with the sample augments (values in `def.json` are themselves variable-expanded, as shown by the hostname):

```
*** ACME Corp - Production - Authorized Use Only ***

  Host <host> is managed by CFEngine; local edits may be reverted.
  Patch window: Sundays 02:00-04:00 UTC.
  All sessions are logged.

Contact: ops@example.com
```

Notes and assumptions:
- Run standalone with `cf-agent -KI -f ./promises.cf`; `def.json` is auto-loaded from the policy's input directory. To drop this into masterfiles instead, delete `promises.cf`, add `motd.cf` to your `inputs`/`services_autorun`, and merge the `variables` block into your existing `def.json`.
- I hardcoded `/etc/motd` since the request asked for three variables governing *content*. Add a fourth guarded pair for `motd_file` if you want the path overridable too.
- On Debian/Ubuntu, `pam_motd` also concatenates `/etc/update-motd.d/` scripts and `/run/motd.dynamic`; this policy only owns the static `/etc/motd`. Disable those scripts if you want the file to be the whole message.
- `perms => mog("0644","root","root")` requires `stdlib.cf` and a root-owned run; my non-root verification run substituted `m("0644")` and a temp path, then I restored the real values and re-checked syntax.