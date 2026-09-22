Wrote three files to the working directory: `motd.cf`, `promises.cf`, and `def.json`.

**Design:** `/etc/motd` is rendered from an inline mustache template fed by three independent variables — `motd_banner`, `motd_contact`, and `motd_warning`. Each has a default in the policy and each is separately overridable from augments; setting one does not require setting the others. The `isvariable()` guard classes are what make the augments override work without the "variable already defined" conflict you get if you try to assign into the bundle twice.

**Verified with the installed agent:** syntax passes `cf-promises`; a run with the full `def.json` renders all three values, a run with no `def.json` falls back to all three defaults, a run setting only `motd_warning` picks that value up while the other two stay default, and a second consecutive run is a no-op (converged, no repair).

`motd.cf`:

```cfengine3
##############################################################################
#
# motd.cf - Manage the content of the message of the day.
#
# Three independent variables drive the content of the file. Each one has a
# sane default in this policy and each one can be overridden individually
# from an augments file (def.json):
#
#   def.motd_banner   - headline shown at the top of the file
#   def.motd_contact  - who to contact about this host
#   def.motd_warning  - access / authorized use notice
#
# Overriding one of them does not require setting the other two.
#
##############################################################################

bundle agent motd
{
  meta:
      "description"
        string => "Manage the content of the message of the day (/etc/motd)";

      "tags" slist => { "motd", "banner", "login" };

  classes:

      # Did the augments file (def.json) provide a value for each variable?

      "motd_have_banner"  expression => isvariable("def.motd_banner");
      "motd_have_contact" expression => isvariable("def.motd_contact");
      "motd_have_warning" expression => isvariable("def.motd_warning");

  vars:

      "file" string => "/etc/motd";

      #
      # Variable 1 of 3: banner
      #
    motd_have_banner::
      "banner" string => "$(def.motd_banner)";
    !motd_have_banner::
      "banner" string => "Welcome to $(sys.fqhost)";

      #
      # Variable 2 of 3: contact
      #
    motd_have_contact::
      "contact" string => "$(def.motd_contact)";
    !motd_have_contact::
      "contact" string => "root@$(sys.fqhost)";

      #
      # Variable 3 of 3: warning
      #
    motd_have_warning::
      "warning" string => "$(def.motd_warning)";
    !motd_have_warning::
      "warning"
        string => "Authorized use only. All activity may be monitored and reported.";

    any::

      # Data passed to the inline mustache template below.

      "data"
        data => mergedata('{
                             "banner":   "$(banner)",
                             "contact":  "$(contact)",
                             "warning":  "$(warning)",
                             "fqhost":   "$(sys.fqhost)",
                             "ipv4":     "$(sys.ipv4)",
                             "flavor":   "$(sys.flavor)",
                             "arch":     "$(sys.arch)"
                           }');

      "template"
        string =>
"##############################################################################
 {{{banner}}}
##############################################################################

 Host     : {{{fqhost}}} ({{{ipv4}}})
 Platform : {{{flavor}}} {{{arch}}}
 Contact  : {{{contact}}}

 {{{warning}}}

 This file is managed by CFEngine. Local edits are reverted.
##############################################################################
";

  files:

      "$(file)"
        create                => "true",
        perms                 => motd_mog("0644", "root", "root"),
        template_method       => "inline_mustache",
        template_data         => @(data),
        edit_template_string  => "$(template)",
        classes               => motd_results("motd_file"),
        comment               => "The message of the day greets and informs
                                  anyone logging in to this host, so its
                                  content must be accurate and consistent.";

  reports:

    motd_file_repaired::
      "$(this.bundle): updated content of $(file)";

    motd_file_failed::
      "$(this.bundle): FAILED to update content of $(file)";

    (DEBUG|DEBUG_motd).!motd_file_failed::
      "$(this.bundle): file    = $(file)";
      "$(this.bundle): banner  = $(banner)";
      "$(this.bundle): contact = $(contact)";
      "$(this.bundle): warning = $(warning)";
}

##############################################################################
# Bodies are namespaced with a motd_ prefix so that this policy file is
# self-contained and can not collide with the standard library.
##############################################################################

body perms motd_mog(mode, owner, group)
{
      mode   => "$(mode)";
      owners => { "$(owner)" };
      groups => { "$(group)" };
      rxdirs => "false";
}

body classes motd_results(class_prefix)
{
      scope            => "namespace";
      promise_kept     => { "$(class_prefix)_kept" };
      promise_repaired => { "$(class_prefix)_repaired" };
      repair_failed    => { "$(class_prefix)_failed" };
}
```

`def.json` (augments — loaded automatically from the directory of the policy entry file):

```json
{
  "variables": {
    "motd_banner": "ACME Corp - Production Infrastructure",
    "motd_contact": "Platform Operations <ops@example.com>, +1-555-0100",
    "motd_warning": "WARNING: Authorized use only. All activity is logged and monitored."
  }
}
```

`promises.cf` (entry point for standalone testing; drop the `motd` bundle into your own bundlesequence when integrating with the MPF):

```cfengine3
##############################################################################
#
# promises.cf - Policy entry point.
#
# def.json, found next to this file, is loaded automatically as the augments
# file and is where the motd variables are configured.
#
##############################################################################

body common control
{
      bundlesequence => { "motd" };
      inputs         => { "motd.cf" };
}
```

Notes:
- Run it with `cf-agent -KIf ./promises.cf`, or `cf-agent -KIf ./promises.cf -D DEBUG_motd` to print the three effective values without inspecting the file.
- To integrate into masterfiles, add `motd.cf` to `inputs` and `"motd"` to your bundlesequence (or call it from `bundle agent main`), then put the three variables in your site's `def.json` — they land in the `def` bundle, which is where the policy reads them.
- Per-host or per-group overrides work the usual augments way: set them in an `augments` include (e.g. `"augments": [ "$(sys.policy_entry_dirname)/site.json" ]`) or guard them with classes in `def.json`.
- The destination path is fixed at `/etc/motd` in `motd.cf:35`; change that one line if you also manage `/etc/motd.d/` or a BSD-style path.