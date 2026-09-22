Both files are in the working directory, syntax-checked with `cf-promises`, and verified with real `cf-agent` runs (once with `def.json` present, once without, using a temp path so I didn't touch the real `/etc/motd`).

**`motd.cf`**

```cfengine3
bundle agent motd
# @brief Manage the content of the message of the day (/etc/motd)
#
# Three independent variables drive the content of the MOTD. Each one has a
# sane built-in default and each one can be overridden independently from
# augments (def.json):
#
#   default:def.motd_banner  - the greeting/identification line
#   default:def.motd_warning - the access/legal notice
#   default:def.motd_contact - who to contact about this host
{
  vars:

      # Where the message of the day lives.
      "path" string => "/etc/motd";

      # 1) Banner ---------------------------------------------------------
      "banner"
        string => "Welcome to $(sys.fqhost)",
        unless => isvariable("default:def.motd_banner");

      "banner"
        string => "$(default:def.motd_banner)",
        if     => isvariable("default:def.motd_banner");

      # 2) Warning --------------------------------------------------------
      "warning"
        string => "Authorized use only. All activity may be monitored and reported.",
        unless => isvariable("default:def.motd_warning");

      "warning"
        string => "$(default:def.motd_warning)",
        if     => isvariable("default:def.motd_warning");

      # 3) Contact --------------------------------------------------------
      "contact"
        string => "root@$(sys.fqhost)",
        unless => isvariable("default:def.motd_contact");

      "contact"
        string => "$(default:def.motd_contact)",
        if     => isvariable("default:def.motd_contact");

      # Assemble the content. The trailing empty element gives the file a
      # terminating newline.
      "lines"
        slist  => {
                    "$(banner)",
                    "",
                    "$(warning)",
                    "",
                    "Contact: $(contact)",
                    "This file is managed by CFEngine. Local edits will be reverted.",
                    "",
                  };

      "content"
        string => join("$(const.n)", "lines");

  files:

      "$(path)"
        create  => "true",
        content => "$(content)",
        perms   => motd_mog("0644", "root", "root"),
        handle  => "motd_content_managed",
        comment => "The message of the day identifies the host and states the
                    conditions of use, so it must have known content.";

  reports:

    verbose_mode|DEBUG::
      "$(this.bundle): managing '$(path)'";
      "$(this.bundle): banner  = '$(banner)'";
      "$(this.bundle): warning = '$(warning)'";
      "$(this.bundle): contact = '$(contact)'";
}

body perms motd_mog(mode, user, group)
# @brief Set mode, owner and group (local copy so this policy is self contained)
{
      mode   => "$(mode)";
      owners => { "$(user)" };
      groups => { "$(group)" };
      rxdirs => "false";
}

bundle agent __main__
# @brief Allow standalone execution: cf-agent -KI -f ./motd.cf
{
  methods:
      "motd";
}
```

**`def.json`**

```json
{
  "variables": {
    "motd_banner": "Welcome to $(sys.fqhost) - production web tier",
    "motd_warning": "Authorized use only. All activity is logged and reviewed.",
    "motd_contact": "ops@example.com"
  }
}
```

Notes:

- The three variables are independent: override any subset in `def.json` and the rest fall back to their defaults (verified both ways). The `if`/`unless isvariable(...)` pair is what makes each one individually overridable rather than all-or-nothing.
- Augments values are themselves expanded, so `$(sys.fqhost)` and other CFEngine variables work inside `def.json`.
- `content` rewrites the whole file, so the MOTD is fully convergent — hand edits get reverted on the next agent run.
- To use it in masterfiles: drop `motd.cf` under `services/`, add it to `inputs` in `promises.cf`, and call `"motd";` from a `methods` promise in `main`. The `__main__` bundle is only there so you can test it standalone with `cf-agent -KI -f ./motd.cf` (the file must not be group/world-writable, or the agent refuses to load it).
- The file path is hardcoded to `/etc/motd`; I kept exactly three augment-configurable variables as asked, all of them content-related. Say the word if you'd like the path made configurable too.