Validated with `cf-promises -cf`, `cfengine lint`, and an actual `cf-agent` run (rendered correctly with both defaults and augments overrides, and converged on the second run).

**Three tunables**, each independently configurable via `def.json`:

| Variable | Purpose | Default |
|---|---|---|
| `motd_organization` | Org name in the banner header | `Northern.tech` |
| `motd_support_contact` | Where users go for help | `admin@example.com` |
| `motd_message` | Free-form / acceptable-use notice | "Unauthorized access is prohibited…" |

Each uses the `isvariable()` + `ifelse()` instrumentation pattern, so the policy has a working default if augments don't define it. (A fourth, `motd_file`, is exposed for testability — not one of the three content tunables.)

### `promises.cf`

```cfengine3
body common control
{
      bundlesequence => { "motd" };

      inputs => {
                  "$(sys.libdir)/stdlib.cf",
                  "services/motd.cf",
                };
}
```

### `services/motd.cf`

```cfengine3
bundle agent motd
{
  meta:
      "description"
        string => "Manage the content of the message of the day.";

  vars:

      # ----------------------------------------------------------------------
      # Tunable 1 of 3: Organization name rendered in the banner.
      # Override by defining 'motd_organization' in augments (def.json).
      # ----------------------------------------------------------------------
      "organization"
        string => ifelse( isvariable( "def.motd_organization" ),
                          "$(def.motd_organization)",
                          "Northern.tech" ),
        comment => "Organization this host belongs to";

      # ----------------------------------------------------------------------
      # Tunable 2 of 3: Who an interactive user should contact for help.
      # Override by defining 'motd_support_contact' in augments (def.json).
      # ----------------------------------------------------------------------
      "support_contact"
        string => ifelse( isvariable( "def.motd_support_contact" ),
                          "$(def.motd_support_contact)",
                          "admin@example.com" ),
        comment => "Support address or phone number printed in the banner";

      # ----------------------------------------------------------------------
      # Tunable 3 of 3: Free form notice, typically the acceptable use banner.
      # Override by defining 'motd_message' in augments (def.json).
      # ----------------------------------------------------------------------
      "message"
        string => ifelse( isvariable( "def.motd_message" ),
                          "$(def.motd_message)",
                          "Unauthorized access is prohibited. All activity may be monitored and recorded." ),
        comment => "Site specific notice rendered below the host details";

      # Path of the file we manage. Not part of the three content tunables, but
      # kept configurable so the policy can be exercised without touching /etc.
      "file"
        string => ifelse( isvariable( "def.motd_file" ),
                          "$(def.motd_file)",
                          "/etc/motd" );

      # Group that owns the file differs on the BSD derived platforms.
      "group"
        string => ifelse( "freebsd|darwin|openbsd|netbsd", "wheel", "root" );

      # Pass only what the template needs. Without an explicit template_data,
      # datastate() is used implicitly, which serializes every variable and
      # class in scope.
      "banner"
        data => parsejson( '{
                              "organization": "$(organization)",
                              "support_contact": "$(support_contact)",
                              "message": "$(message)",
                              "fqhost": "$(sys.fqhost)",
                              "ipaddress": "$(sys.ipv4)",
                              "os": "$(sys.class)",
                              "file": "$(file)"
                            }' );

      "template"
        string => concat( "$(const.n)",
                          "  {{{organization}}}$(const.n)",
                          "$(const.n)",
                          "  Host    : {{{fqhost}}} ({{{ipaddress}}})$(const.n)",
                          "  Platform: {{{os}}}$(const.n)",
                          "  Support : {{{support_contact}}}$(const.n)",
                          "$(const.n)",
                          "  {{{message}}}$(const.n)",
                          "$(const.n)",
                          "  This host is managed by CFEngine. Local edits to {{{file}}} are$(const.n)",
                          "  reverted on the next agent run.$(const.n)",
                          "$(const.n)" );

  files:

      "$(file)"
        create => "true",
        edit_template_string => "$(template)",
        template_method => "inline_mustache",
        template_data => @(banner),
        perms => mog( "0644", "root", "$(group)" ),
        classes => results( "bundle", "motd_file" ),
        comment => "The message of the day must reflect the configured banner";

  reports:

    motd_file_repaired::
      "Updated $(file) for '$(organization)'";

    motd_file_failed::
      "Failed to update $(file)";
}
```

### `def.json`

```json
{
  "variables": {
    "motd_organization": {
      "value": "Northern.tech",
      "comment": "Organization name rendered at the top of the message of the day",
      "tags": [ "motd" ]
    },
    "motd_support_contact": {
      "value": "admin@example.com",
      "comment": "Where interactive users should go for help with this host",
      "tags": [ "motd" ]
    },
    "motd_message": {
      "value": "Unauthorized access is prohibited. All activity may be monitored and recorded.",
      "comment": "Site specific notice, typically the acceptable use banner",
      "tags": [ "motd" ]
    }
  }
}
```

Notes:
- `.cf` files are mode `600` — `cf-agent` refuses group/world-writable policy.
- The three values are rendered through `inline_mustache` with an explicit `template_data`, using triple-mustache (`{{{ }}}`) so `&`, `<` etc. in a contact string or notice aren't HTML-escaped.
- Because they're plain `def` variables, per-host overrides also work through Enterprise CMDB (`host_specific.json`) or a class-guarded augments include, without touching the policy.