Policy validates cleanly and the augments override was confirmed via `--show-evaluated-vars` (the dry run only failed on `/etc/motd` due to lacking root permission in this sandbox, which is expected).

## Files written

**`motd.cf`**
```cfengine3
bundle agent motd
# @brief Manage the system's message of the day (/etc/motd)
{
  vars:
      # Tunable via augments -- policy reads from def, falls back to default
      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                          "$(def.motd_organization)",
                          "Example Corp"),
        comment => "Organization name shown in the message of the day";

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                          "$(def.motd_support_contact)",
                          "support@example.org"),
        comment => "Support contact address shown in the message of the day";

      "banner_message"
        string => ifelse(isvariable("def.motd_banner_message"),
                          "$(def.motd_banner_message)",
                          "Authorized users only. All activity may be monitored and reported."),
        comment => "Warning/banner text shown in the message of the day";

      "content"
        string => "$(banner_message)$(const.n)$(const.n)Managed by $(organization) -- contact $(support_contact) for assistance.$(const.n)",
        comment => "Assembled content for /etc/motd";

  files:
      "/etc/motd"
        create        => "true",
        content       => "$(content)",
        perms         => motd_perms;
}

body perms motd_perms
{
      mode    => "644";
      owners  => { "root" };
      groups  => { "root" };
}
```

**`promises.cf`** (entry point)
```cfengine3
body common control
{
      bundlesequence  => { "motd" };
      inputs          => { "motd.cf" };
}
```

**`def.json`** (example augments override)
```json
{
  "vars": {
    "motd_organization": "Northern.tech",
    "motd_support_contact": "admin@example.com",
    "motd_banner_message": "Authorized users only. All activity may be monitored and reported."
  }
}
```

## Notes

- Three independent, augment-tunable variables: `organization`, `support_contact`, `banner_message`. Each falls back to a sensible default via the `isvariable()`/`ifelse()` pattern if `def.json` doesn't define it.
- `content` assembles the final `/etc/motd` text from the three variables and is written via the `content =>` file attribute (writes the whole file from a string, CFEngine 3.10+).
- Validated with `cf-promises -cf`, `cf-promises --full-check`, and a `cf-agent -KIf` dry run confirming the augments values (`Northern.tech`, `admin@example.com`) were correctly substituted; the only failure was a permission-denied on `/etc/motd` since this sandbox session isn't root.