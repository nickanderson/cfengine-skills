All three files are in place under the working directory and I've validated the policy end-to-end with `cf-agent` (syntax check, and actual runs covering all-defaults, single-variable override, and full-augment override — including catching and fixing a real newline-escaping bug in the process).

## Summary

The policy manages `/etc/motd` from three independent variables, each overridable via an augments file (`def.json`) without touching the `.cf` files:

- `def.motd_message` — greeting text at the top
- `def.motd_show_sysinfo` — `"true"`/`"false"`, whether to append a live hostname/OS/kernel line
- `def.motd_footer` — closing notice at the bottom

Each variable falls back to a sensible built-in default via `ifelse(isvariable(...), ...)` when not set in `def.json`, so any subset can be overridden independently.

**`promises.cf`**
```cfengine3
#############################################################################
# promises.cf
#
# Entry point. Runs the motd bundle, which manages /etc/motd. Variables
# controlling its content can be overridden via the augments file def.json
# in this same directory, without editing any .cf file.
#############################################################################

body common control
{
      bundlesequence  => { "motd" };
      inputs          => { "services/motd.cf" };
}
```

**`services/motd.cf`**
```cfengine3
#############################################################################
# services/motd.cf
#
# Manages /etc/motd from three independent, augment-configurable variables:
#
#   def.motd_message       - greeting text shown at the top of the file
#   def.motd_show_sysinfo  - "true"/"false", whether to append a live
#                             hostname/OS/kernel line
#   def.motd_footer        - closing notice shown at the bottom of the file
#
# Any of the three may be overridden per-host/per-group via an augments
# file (def.json) without editing this policy. See def.json in this
# directory for an example.
#############################################################################

bundle agent motd
{
  vars:

      "message"
        string => ifelse(isvariable("def.motd_message"),
                          "$(def.motd_message)",
                          "Welcome to $(sys.fqhost)"),
        comment => "Greeting text at the top of /etc/motd. Override via def.json as def.motd_message.";

      "show_sysinfo"
        string => ifelse(isvariable("def.motd_show_sysinfo"),
                          "$(def.motd_show_sysinfo)",
                          "true"),
        comment => "Whether to append a live system info line. Override via def.json as def.motd_show_sysinfo.";

      "footer"
        string => ifelse(isvariable("def.motd_footer"),
                          "$(def.motd_footer)",
                          "Unauthorized use of this system is prohibited."),
        comment => "Closing notice at the bottom of /etc/motd. Override via def.json as def.motd_footer.";

      "sysinfo_line"
        string => "$(sys.fqhost) -- $(sys.ostype) $(sys.flavor), kernel $(sys.release)",
        comment => "Rendered system information line, included only when show_sysinfo is enabled.";

      "content"
        string => ifelse(strcmp("$(motd.show_sysinfo)", "true"),
                          format("%s$(const.n)$(const.n)%s$(const.n)$(const.n)%s$(const.n)",
                                 "$(motd.message)", "$(motd.sysinfo_line)", "$(motd.footer)"),
                          format("%s$(const.n)$(const.n)%s$(const.n)",
                                 "$(motd.message)", "$(motd.footer)")),
        comment => "Full rendered /etc/motd content, assembled from the three variables above.";

  files:

      "/etc/motd"
        create  => "true",
        content => "$(motd.content)",
        comment => "Render /etc/motd from the message, show_sysinfo and footer variables.";
}
```

**`def.json`** (example augments — delete or edit any key to fall back to policy defaults)
```json
{
  "vars": {
    "motd_message": "Welcome to the Example Corp infrastructure.",
    "motd_show_sysinfo": "true",
    "motd_footer": "All activity may be monitored and reported. Contact ops@example.com for support."
  }
}
```

Two implementation notes worth knowing if you extend this:
- CFEngine string literals don't interpret `\n` as a newline — I used the built-in `$(const.n)` special variable instead.
- The `content` file-promise attribute (CFEngine ≥3.15) was used instead of `edit_line`/`insert_lines`, since `insert_lines` dedupes identical lines (e.g. blank-line separators), which silently drops repeated blank lines.