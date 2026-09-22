Written to `/tmp/cfeval-01-motd-no-skill.oAiUerWv/work` and verified with CFEngine 3.27.1 (`cf-promises` clean; `cf-agent` run against a temp path renders correctly, is idempotent on the second run, and falls back to the defaults when `def.json` is absent).

The three independent, augments-configurable variables are `def.motd_banner` (string), `def.motd_notices` (list), and `def.motd_contact` (string). Each is optional and has its own fallback, so you can set any subset.

**`motd.cf`**

```cfengine3
bundle agent motd
# @brief Manage the content of the message of the day (/etc/motd)
#
# The content is built from three independent variables, each of which can be
# overridden from augments (def.json) without editing this policy:
#
#   def.motd_banner   (string) - the headline shown at the top of the motd
#   def.motd_notices  (slist)  - zero or more notice lines shown as a list
#   def.motd_contact  (string) - who to contact, shown at the bottom
#
# Each variable falls back to a sane default when it is not defined in
# augments, so the policy is safe to run with no def.json at all.
{
  meta:
      "description"
        string => "Manage the content of the message of the day";

      "tags" slist => { "autorun", "motd", "banner" };

  vars:

    #### Variable 1 of 3: the banner line ####

      "banner"
        string => "$(def.motd_banner)",
        if => isvariable( "def.motd_banner" ),
        comment => "Use the banner supplied by augments when it is defined.";

      "banner"
        string => "Welcome to $(sys.fqhost) ($(sys.flavor) $(sys.arch))",
        unless => isvariable( "def.motd_banner" ),
        comment => "Fall back to a host specific banner.";

    #### Variable 2 of 3: the notice lines ####

      "notices"
        slist => { "@(def.motd_notices)" },
        if => isvariable( "def.motd_notices" ),
        comment => "Use the notices supplied by augments when they are defined.";

      "notices"
        slist => { "This system is managed by CFEngine, local modifications may be reverted.",
                   "Unauthorized use is prohibited and may be logged." },
        unless => isvariable( "def.motd_notices" ),
        comment => "Fall back to a generic set of notices.";

    #### Variable 3 of 3: the contact information ####

      "contact"
        string => "$(def.motd_contact)",
        if => isvariable( "def.motd_contact" ),
        comment => "Use the contact supplied by augments when it is defined.";

      "contact"
        string => "root@$(sys.fqhost)",
        unless => isvariable( "def.motd_contact" ),
        comment => "Fall back to the local root user.";

    #### Where the content lives ####

      "motd_file"
        string => "/etc/motd";

      "template"
        string => "$(this.promise_dirname)/templates/motd.mustache";

    #### Render the three variables into template data ####

      # JSON escape the free form strings so that a double quote or a
      # backslash in an augments supplied value can not corrupt the data.
      "esc[banner]"
        string => string_replace( string_replace( "$(banner)", "\\", "\\\\" ),
                                  "\"", "\\\"" );

      "esc[contact]"
        string => string_replace( string_replace( "$(contact)", "\\", "\\\\" ),
                                  "\"", "\\\"" );

      # storejson() takes care of escaping each element of the list for us.
      "notices_data" data   => mergedata( "notices" );
      "notices_json" string => storejson( "notices_data" );

      "template_data"
        data => parsejson( '{
                              "banner":  "$(esc[banner])",
                              "notices": $(notices_json),
                              "contact": "$(esc[contact])"
                            }' );

  files:

      "$(motd_file)"
        create => "true",
        perms => mog( "0644", "root", "root" ),
        edit_template => "$(template)",
        template_method => "mustache",
        template_data => @(template_data),
        classes => results( "bundle", "motd_content" ),
        comment => "The message of the day informs anyone logging in about the
                    ownership and the acceptable use of this host.";

  reports:
    motd_content_repaired::
      "$(this.bundle): Updated the content of '$(motd_file)'";

    motd_content_failed|motd_content_denied::
      "$(this.bundle): Unable to manage the content of '$(motd_file)'";

    inform_mode::
      "$(this.bundle): banner  = '$(banner)'";
      "$(this.bundle): notice  = '$(notices)'";
      "$(this.bundle): contact = '$(contact)'";
}
```

**`templates/motd.mustache`**

```mustache
{{{banner}}}
{{#notices}}
  * {{{.}}}
{{/notices}}
Questions or problems? Contact {{{contact}}}
```

**`def.json`**

```json
{
  "variables": {
    "motd_banner": "*** ACME production build host ***",

    "motd_notices": [
      "Unauthorized access is prohibited and is logged.",
      "This host is managed by CFEngine, local changes may be reverted.",
      "Scheduled maintenance window: Sundays 02:00-04:00 UTC."
    ],

    "motd_contact": "the platform team <ops@example.com>"
  }
}
```

**`promises.cf`** (standalone entry point for testing; in the MPF you'd instead add `motd.cf` to inputs and let autorun or `services/main.cf` call the bundle)

```cfengine3
body common control
# @brief Stand alone entry point, useful for testing:
#        cf-agent -KI -f ./promises.cf
{
      bundlesequence => { "motd" };

      inputs => { "$(sys.libdir)/stdlib.cf",
                  "motd.cf" };
}
```

Rendered output with the sample `def.json`:

```
*** ACME production build host ***
  * Unauthorized access is prohibited and is logged.
  * This host is managed by CFEngine, local changes may be reverted.
  * Scheduled maintenance window: Sundays 02:00-04:00 UTC.
Questions or problems? Contact the platform team <ops@example.com>
```

A couple of assumptions worth flagging: the target path is hardcoded to `/etc/motd` since you asked for exactly three content variables — on Debian/Ubuntu the login banner is assembled by `pam_motd` from `/etc/update-motd.d/` plus `/etc/motd`, so this manages the static part only. `README.md` in the same directory covers that and the MPF integration steps.