Wrote `motd.cf`, `def.json`, and `README.md` to the working directory. Both code paths were tested with CFEngine 3.27.1 — defaults, augments overrides, and a convergent second run (no changes).

**`motd.cf`**

```cfengine3
bundle agent motd
# @brief Manage the content of the message of the day (motd)
#
# Three independent variables drive this policy. Each one can be overridden
# from augments (def.json) without editing the policy itself:
#
#   default:def.motd_path    - full path to the motd file
#   default:def.motd_banner  - banner (first line) shown to the user
#   default:def.motd_contact - who to contact about this host
#
# @see ./def.json for an example augments file
{
  vars:

      # 1) Where the message of the day lives.
      "path"
        string => ifelse( isvariable( "def.motd_path" ),
                          "$(def.motd_path)",
                          "/etc/motd" ),
        comment => "Override by defining default:def.motd_path in augments";

      # 2) The banner, the first thing presented to the user.
      "banner"
        string => ifelse( isvariable( "def.motd_banner" ),
                          "$(def.motd_banner)",
                          "Welcome to $(sys.fqhost)" ),
        comment => "Override by defining default:def.motd_banner in augments";

      # 3) Who to contact with questions about this host.
      "contact"
        string => ifelse( isvariable( "def.motd_contact" ),
                          "$(def.motd_contact)",
                          "root@$(sys.fqhost)" ),
        comment => "Override by defining default:def.motd_contact in augments";

      # The full content, assembled from the three variables above.
      "content"
        string => "$(banner)$(const.n)$(const.n)Host:    $(sys.fqhost) ($(sys.ipv4))$(const.n)OS:      $(sys.flavor)$(const.n)Contact: $(contact)$(const.n)",
        comment => "Rendered once so that the files promise below stays simple
                    and convergent";

  files:

      "$(path)"
        create => "true",
        content => "$(content)",
        perms => mog( "0644", "root", "root" ),
        handle => "motd_content",
        comment => "The message of the day is presented at login. It should
                    always reflect what policy and augments define, so that
                    local edits do not persist.";

  reports:

    verbose_mode::
      "$(this.bundle): managing '$(path)' with banner '$(banner)' and contact '$(contact)'";
}

bundle agent __main__
# @brief Entry point when the policy is run directly
#
#     cf-agent --no-lock --inform --file ./motd.cf
{
  methods:
      "motd";
}

body file control
{
      inputs => { "$(sys.libdir)/stdlib.cf" };
}
```

**`def.json`**

```json
{
  "variables": {
    "default:def.motd_path": "/etc/motd",
    "default:def.motd_banner": "*** Example Corp - authorized use only ***",
    "default:def.motd_contact": "ops@example.com"
  }
}
```

Notes on the choices I made:

- The three variables are `motd_path`, `motd_banner`, and `motd_contact` — file location, headline text, and support contact. They are independent: overriding one in augments leaves the other two on their defaults.
- I used `ifelse(isvariable(...), ...)` rather than `default()` because `default()` is not in the function set of this CFEngine build (`cf-promises -s json` lists 200 functions, no `default`); `ifelse` resolves correctly whether or not the augments variable exists.
- `content` (rather than `edit_template`) keeps the policy self-contained — no template file to distribute — and remains convergent; a re-run after the file matched reported no changes.
- Ownership is enforced as `root:root 0644` via stdlib's `mog`. My test runs were unprivileged, so the ownership repair failed there as expected; content and mode were correct.

Run it standalone with `cf-agent --no-lock --inform --file ./motd.cf`, or drop `motd.cf` into your masterfiles, add it to `inputs`, call `"motd";` from a `methods:` promise, and merge the `variables` block into your masterfiles `def.json`.