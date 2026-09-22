Files written to `/tmp/cfeval-01-motd-with-skill.rUXDB3I6/work`: `promises.cf`, `motd.cf`, `def.json`.

**Design:** three independent tunables — `motd_organization`, `motd_support_contact`, `motd_legal_notice` — each instrumented with the `isvariable()` + `ifelse()` pattern so the policy carries a working default and any one of them can be overridden from `def.json` (or `host_specific.json`) without touching the others. Content is rendered with `inline_mustache` and an explicit `template_data` container so the implicit, expensive `datastate()` is never used. The container is built from a classic array rather than a JSON string literal, so values containing quotes or other JSON-significant characters can't corrupt it.

**Verified:** `cf-promises --full-check` and `cfengine lint` both pass; a scratch-path copy rendered correctly both with `def.json` present (Northern.tech values) and with it removed (policy defaults).

`promises.cf`
```cfengine3
##############################################################################
#
# promises.cf - Policy entry point for the MOTD example.
#
# def.json, adjacent to this file, is loaded automatically as augments.
#
##############################################################################

body common control
{
      bundlesequence => { "motd" };
      inputs         => { "motd.cf" };
}
```

`motd.cf`
```cfengine3
##############################################################################
#
# motd.cf - Manage the Message Of The Day (/etc/motd)
#
# Three independent, augments-tunable variables drive the content:
#
#   def.motd_organization    - Organization name shown in the banner
#   def.motd_support_contact - Where users should go for help
#   def.motd_legal_notice    - Legal / acceptable use notice
#
# Each has a policy default, so the policy is complete on its own. Any of the
# three can be overridden independently from def.json (or host_specific.json)
# without touching this file.
#
##############################################################################

bundle agent motd
{
  vars:

      # --- Tunables -----------------------------------------------------
      # Read from the def bundle when augments supplied a value, otherwise
      # fall back to the default baked into policy.

      "_organization"
        string => ifelse( isvariable( "def.motd_organization" ),
                          "$(def.motd_organization)",
                          "Example Organization" ),
        comment => "Organization name rendered in the MOTD banner";

      "_support_contact"
        string => ifelse( isvariable( "def.motd_support_contact" ),
                          "$(def.motd_support_contact)",
                          "support@example.com" ),
        comment => "Support address or URL rendered in the MOTD";

      "_legal_notice"
        string => ifelse( isvariable( "def.motd_legal_notice" ),
                          "$(def.motd_legal_notice)",
                          "Unauthorized access is prohibited. All activity may be monitored and recorded." ),
        comment => "Legal / acceptable use notice rendered in the MOTD";

      # --- Template data -------------------------------------------------
      # Built from a classic array so that values containing quotes, colons
      # or other JSON-significant characters can not corrupt the container.

      "_d[organization]"    string => "$(_organization)";
      "_d[support_contact]" string => "$(_support_contact)";
      "_d[legal_notice]"    string => "$(_legal_notice)";
      "_d[fqhost]"          string => "$(sys.fqhost)";
      "_d[os]"              string => "$(sys.flavor)";
      "_d[arch]"            string => "$(sys.arch)";

      "_template_data"
        data => mergedata( "_d" ),
        comment => "Only the values the template needs, so that the implicit
                    and expensive datastate() is never used";

      "_template"
        string => concat( "$(const.n)",
                          "  $(_organization)$(const.n)",
                          "$(const.n)",
                          "  Host    : {{{fqhost}}} ({{{os}}} {{{arch}}})$(const.n)",
                          "  Support : {{{support_contact}}}$(const.n)",
                          "$(const.n)",
                          "  {{{legal_notice}}}$(const.n)",
                          "$(const.n)",
                          "  This file is managed by CFEngine.$(const.n)",
                          "  Local modifications will be reverted.$(const.n)",
                          "$(const.n)" ),
        comment => "Inline mustache template for the MOTD body";

      # Inventory so the hub can report which banner a host is carrying.
      "_inventory_organization"
        string => "$(_organization)",
        meta => { "inventory", "attribute_name=MOTD Organization" };

  files:

      "/etc/motd"
        create               => "true",
        template_method      => "inline_mustache",
        edit_template_string => "$(_template)",
        template_data        => @(_template_data),
        perms                => motd_perms( "0644", "root", "root" ),
        classes              => motd_results( "motd_file" ),
        comment              => "The MOTD is rendered from the three tunables above";

  reports:

    motd_file_repaired::
      "Updated /etc/motd for '$(_organization)'";

    inform_mode::
      "MOTD tunables: organization='$(_organization)' support='$(_support_contact)' legal='$(_legal_notice)'";
}

##############################################################################
# Bodies (locally named so the policy is self contained and never collides
# with the standard library).
##############################################################################

body perms motd_perms(mode, user, group)
{
      mode   => "$(mode)";
      rxdirs => "false";
      owners => { "$(user)" };
      groups => { "$(group)" };
}

body classes motd_results(prefix)
# Define namespace scoped outcome classes for the promise.
{
      promise_repaired => { "$(prefix)_repaired" };
      repair_failed    => { "$(prefix)_failed" };
      repair_denied    => { "$(prefix)_failed" };
      repair_timeout   => { "$(prefix)_failed" };
      promise_kept     => { "$(prefix)_kept" };
      scope            => "namespace";
}
```

`def.json`
```json
{
  "variables": {
    "motd_organization": {
      "value": "Northern.tech",
      "comment": "Organization name rendered in the MOTD banner",
      "tags": [ "motd" ]
    },
    "motd_support_contact": {
      "value": "admin@example.com or x4357",
      "comment": "Where users should go for help",
      "tags": [ "motd" ]
    },
    "motd_legal_notice": {
      "value": "Authorized use only. All activity on this system may be monitored and recorded.",
      "comment": "Legal / acceptable use notice rendered in the MOTD",
      "tags": [ "motd" ]
    }
  }
}
```

Two notes worth flagging: the file path `/etc/motd` is intentionally *not* a tunable, since you asked for exactly three content variables — say the word if you want it configurable too. And on Debian/Ubuntu, `pam_motd` also concatenates `/etc/update-motd.d/*` scripts into the displayed banner, so you may want those disabled for the rendered file to be what users actually see.