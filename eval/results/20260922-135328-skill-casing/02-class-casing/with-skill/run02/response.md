## Answer

No — CFEngine class names and class expressions are strictly case-sensitive, and there's no flag or operator to make matching case-insensitive. `has_nginx`, `has_Nginx`, and `has_NGINX` are three distinct classes, permanently.

The fix isn't to make matching insensitive — it's to normalize *once*, at the point where you turn inventory data into a class name. Read each service name, run it through `string_downcase()` + `canonify()`, and use *that* as the class name (`has_nginx` no matter whether the source said `Nginx`, `nginx`, or `NGINX`). Everything downstream — bundle names, `only_if` expressions — is then written in that one canonical lowercase form and always matches.

Crucially, don't downcase the *whole* `only_if` expression — only the class name you're defining. `only_if` strings also reference correctly-cased hard classes like `Monday`/`Tuesday`; downcasing those turns them into classes that never fire.

## Implementation notes

A subtlety came up while testing: a `vars:` promise that references a JSON key which is absent for some inventory entries (e.g. `only_if` when a service has none) doesn't just yield an empty string — it fails to resolve at all, since CFEngine expands string/function arguments eagerly. `ifelse(isvariable(...), "$(maybe_missing)", "any")` does **not** protect against this, because `ifelse()` still eagerly evaluates the `"$(maybe_missing)"` argument even on the false branch. The fix is two `if =>`-guarded vars promises (one per case) instead of a ternary — a false class guard skips the promise's RHS evaluation entirely. I verified this by watching `svc_nginx` (no `only_if`) silently fail to run until I switched to the guarded form.

I wrote `/tmp/.../work/policy.cf` and `inventory.json`, validated with `cf-promises --full-check`, and ran `cf-agent -K -f ./policy.cf` against the example inventory plus mixed-casing, `maintenance: true`, and weekend `only_if` variants — all behaved as expected.

```cfengine3
#######################################################
#
# Run per-host service bundles from an inventory export,
# tolerating any casing of service names in the data.
#
#######################################################

body common control
{
      bundlesequence => { "main" };
}

#######################################################

bundle agent main
# @brief Read inventory.json, define has_<service> classes with a
# canonical (lowercase) name regardless of the casing used by the
# inventory data, and run each service's bundle when it is listed,
# its only_if expression (if any) is true, and the host is not in
# maintenance.
{
  vars:
      "inventory"
        data => readjson("$(this.promise_dirname)/inventory.json", 1000000);

      "idx"
        slist => getindices("inventory[services]");

      # Canonical (lowercase, canonified) service id, independent of
      # how the inventory data cased the service name.
      "id[$(idx)]"
        string => canonify(string_downcase("$(inventory[services][$(idx)][name])"));

      "keys[$(idx)]"
        slist => getindices("inventory[services][$(idx)]");

  classes:
      "maintenance"
        expression => strcmp("$(inventory[maintenance])", "true");

      # One class per inventory entry, always named in lowercase, no
      # matter whether the data said "Nginx", "nginx" or "NGINX".
      "has_$(id[$(idx)])"
        expression => "any";

      # Whether this entry carries an only_if key at all. Checked via
      # the key list, never via the (possibly absent) value itself --
      # referencing a missing "only_if" value directly would leave the
      # whole promise unresolved instead of just false.
      "has_only_if_$(idx)"
        expression => some("^only_if$", "keys[$(idx)]");

  vars:
      # The only_if expression as written by the inventory team, used
      # as-is (it already refers to our lowercase has_* classes and to
      # correctly-cased hard classes like Monday). Entries without an
      # only_if default to "any". Each promise is guarded so only the
      # branch that is safe to expand is ever evaluated.
      "only_if[$(idx)]"
        string => "$(inventory[services][$(idx)][only_if])",
        if => "has_only_if_$(idx)";

      "only_if[$(idx)]"
        string => "any",
        if => "!has_only_if_$(idx)";

      # Parenthesize the data-supplied expression: "." binds tighter
      # than "|", so without parens "!maintenance.has_x.a|b" would
      # mean "(!maintenance.has_x.a)|b" instead of requiring all three.
      "run_expr[$(idx)]"
        string => "!maintenance.has_$(id[$(idx)]).($(only_if[$(idx)]))";

      "bundle[$(idx)]"
        string => "svc_$(id[$(idx)])";

  methods:
      "$(idx)"
        usebundle => "$(bundle[$(idx)])",
        if => "$(run_expr[$(idx)])";
}

#######################################################
# Service bundle stubs
#######################################################

bundle agent svc_nginx
{
  reports:
      "CONFIGURED: svc_nginx";
}

bundle agent svc_postgresql
{
  reports:
      "CONFIGURED: svc_postgresql";
}

bundle agent svc_node_exporter
{
  reports:
      "CONFIGURED: svc_node_exporter";
}

bundle agent svc_log_shipper
{
  reports:
      "CONFIGURED: svc_log_shipper";
}

bundle agent svc_backup_agent
{
  reports:
      "CONFIGURED: svc_backup_agent";
}

bundle agent svc_redis
{
  reports:
      "CONFIGURED: svc_redis";
}
```

And `inventory.json` (the example from the prompt):

```json
{
  "maintenance": false,
  "services": [
    { "name": "Nginx" },
    { "name": "Node-Exporter", "only_if": "has_nginx|has_postgresql" },
    { "name": "Log-Shipper",   "only_if": "(has_nginx|has_postgresql).(Monday|Tuesday|Wednesday|Thursday|Friday)" },
    { "name": "Backup-Agent",  "only_if": "has_postgresql.(Saturday|Sunday)" }
  ]
}
```

Both files are in the working directory. Running `cf-agent -K -f ./policy.cf` against this data on a Tuesday reports `svc_nginx`, `svc_node_exporter`, and `svc_log_shipper` configured — `svc_backup_agent` correctly stays off since `postgresql` isn't in this host's inventory.