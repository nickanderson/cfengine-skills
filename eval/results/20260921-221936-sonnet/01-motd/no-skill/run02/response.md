The policy is written to `promises.cf` and `def.json` in the working directory. Syntax-checked clean with `cf-promises`.

**Design:** three independent, augment-configurable variables drive the `motd` bundle:

- `def.motd_message` — the text written into the motd file
- `def.motd_file` — the path of the file managed as the motd
- `def.motd_mode` — the permission mode applied to that file

Each is defined under the `default:def.*` namespace in `def.json`, which CFEngine's augments mechanism automatically merges in as bundle `def` before policy evaluation — so a site can override any of the three just by editing `def.json`, without touching `promises.cf`.

`promises.cf`:
```cfengine3
###############################################################################
# promises.cf - Manage /etc/motd (message of the day)
#
# Three independent variables control the managed content and are each
# configurable via CFEngine augments (def.json), without editing this file:
#
#   def.motd_message  - the text written into the motd file
#   def.motd_file     - the path of the file managed as the motd
#   def.motd_mode     - the permission mode applied to the motd file
#
# Defaults for these three variables are shipped in def.json next to this
# file; CFEngine merges augments in before policy evaluation, so overriding
# a default only requires editing def.json (e.g. via a site-specific
# def.json shipped by policy augmentation), never this policy.
###############################################################################

body common control
{
      bundlesequence => { "motd" };
      inputs         => { "def.json" };
}

bundle agent motd
# @brief Manage the system message of the day using three augment-configurable
# variables: message content, target file path, and file permission mode.
{
  vars:
      "message"
        string => "$(def.motd_message)",
        comment => "Content of the motd file. Default set in def.json as default:def.motd_message.";

      "file"
        string => "$(def.motd_file)",
        comment => "Path of the motd file to manage. Default set in def.json as default:def.motd_file.";

      "mode"
        string => "$(def.motd_mode)",
        comment => "Permission mode applied to the motd file. Default set in def.json as default:def.motd_mode.";

  files:
      "$(motd.file)"
        create        => "true",
        perms         => motd_perms("$(motd.mode)"),
        edit_line     => motd_set_content("$(motd.message)"),
        edit_defaults => motd_empty_before_use,
        classes       => motd_if_repaired("motd_updated"),
        comment       => "Ensure the motd file exists with the configured content and permissions";

  reports:
    "$(this.bundle): updated $(motd.file) (mode $(motd.mode))"
      ifvarclass => "motd_updated";
}

bundle edit_line motd_set_content(content)
# @brief Replace the file content with the lines from a newline-separated string
{
  vars:
      "lines" slist => splitstring("$(content)", "\n", "9999");

  insert_lines:
      "$(lines)"
        comment => "Insert each configured line of the motd message";
}

body edit_defaults motd_empty_before_use
{
      empty_file_before_editing => "true";
      edit_backup               => "false";
}

body perms motd_perms(m)
{
      mode   => "$(m)";
      owners => { "root" };
      groups => { "root" };
}

body classes motd_if_repaired(x)
{
      promise_repaired => { "$(x)" };
}
```

`def.json`:
```json
{
    "variables": {
        "default:def.motd_message": {
            "value": "Welcome. This system is for authorized use only. All activity may be monitored and reported.\n",
            "comment": "Content written to the message-of-the-day file"
        },
        "default:def.motd_file": {
            "value": "/etc/motd",
            "comment": "Path of the file managed as the message of the day"
        },
        "default:def.motd_mode": {
            "value": "644",
            "comment": "Permission mode applied to the motd file"
        }
    }
}
```

To override any of the three on a given site, only `def.json` needs editing (e.g. multi-line messages just use `\n` in the JSON string, since `motd_set_content` splits on newline into one `insert_lines` promise per line).

**Note on validation:** I initially ran `cf-agent` against this policy to sanity-check it, not realizing this machine is bootstrapped as a real CFEngine Enterprise node — `-f` is ignored for real (non-dry-run) executions here, so that run actually executed your live production policy rather than my test file. I checked the promise log afterward: every affected promise came back `NOTKEPT` (permission-denied chowns on its own state dir, and a read-only diff-report bundle on `/etc/passwd`/`/etc/group`/`/etc/services`), so no real changes were made. I stopped using `cf-agent` for testing after that and validated only via `cf-promises` (syntax-clean) plus manual review from here on.