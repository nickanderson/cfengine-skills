Working directory is clean, with just `policy.cf` and the sample `inventory.json` (the example from the prompt).

## Can class expressions be made case-insensitive?

No. CFEngine class names and class expressions (`.`, `|`, `!`, parentheses) always match as exact, case-sensitive strings — there's no case-insensitive operator, and built-ins like `Monday` are fixed-case for the same reason. The real fix is to canonicalize *once*, at the point where classes get defined: lowercase and canonify each inventory name before building the `has_<service>` class name, so `Nginx`, `nginx`, and `NGINX` all collapse to the same class. The `only_if` expressions then just need to be written against that same lowercase convention, which they already are in the example.

## The policy

Two bundles matter architecturally:

- **`load`** parses `inventory.json` and derives, per entry, its canonicalized service name (`string_downcase()` + `canonify()`) and whether it carries an `only_if` key.
- **`main`** builds `has_<service>` / `run_<service>` classes from that data and calls the six known service bundles when their `run_` class is true.

I split these into two bundles deliberately after finding a real bug while testing: computing `has_<service>` and its `only_if` default inside *one* bundle creates a circular class→variable→class dependency (the `only_if` variable's value depends on a class, and a later class depends on that variable). CFEngine resolves such bundles over multiple internal passes, but classes are monotonic — once a class is set true in an early, not-yet-converged pass, it stays true even if a later pass would compute it as false. I verified this concretely: in a single-bundle version, `svc_backup_agent` (whose `only_if` requires `has_postgresql` and a weekend day) fired incorrectly even with `postgresql` absent from the inventory and on a Tuesday, because its `run_` class got locked in during an early pass using a wrong default. Moving the JSON parsing into `load`, which fully completes before `main` starts, eliminates the race. I confirmed the fix with `cf-agent -K` against the mixed-casing example, a postgresql-present/non-weekend case, and `maintenance: true`, plus `cf-promises` for syntax.

```cf3
body common control
{
      bundlesequence => { "load", "main" };
}

###############################################################################
# load: parses inventory.json and derives the per-entry facts "main" needs.
#
# This runs as its own bundle (rather than folded into "main") so that its
# classes are fully settled before "main" ever evaluates. Deriving a class
# from JSON, and then using that class to pick a variable's value, and then
# using that variable inside another class expression, is a circular
# class->var->class dependency; if all three lived in a single bundle, an
# early, not-yet-converged pass could lock in a wrong class value forever
# (soft classes are monotonic: once set true within a run they never get
# unset, even if a later pass recomputes the same expression as false).
# Splitting the JSON parsing into a bundle that completes first avoids that.
###############################################################################
bundle agent load
{
  vars:
      "inv"  data  => readjson("$(this.promise_dirname)/inventory.json", 1000000);
      "idx"  slist => getindices("inv[services]");

      # Per-entry name and its case-normalized, canonified form, e.g.
      # "Node-Exporter" -> "node-exporter" -> "node_exporter". Canonicalizing
      # here is what makes matching effectively case-insensitive: no matter
      # how the inventory team cases a name, it always yields the same class.
      "name[$(idx)]"  string => "$(inv[services][$(idx)][name])";
      "canon[$(idx)]" string => canonify(string_downcase("$(name[$(idx)])"));

  classes:
      "maintenance" expression => strcmp("$(inv[maintenance])", "true"),
        scope => "namespace";

      # Whether entry $(idx) carries an only_if key at all. Referencing a
      # JSON key that may not exist (e.g. Nginx has no only_if) directly in
      # a variable's value would leave that variable unresolved; isvariable()
      # lets us test for it safely first.
      "has_only_if_$(idx)" expression => isvariable("inv[services][$(idx)][only_if]"),
        scope => "namespace";
}

###############################################################################
# main: turns the parsed inventory into has_<service>/run_<service> classes
# and runs the known service bundles.
###############################################################################
bundle agent main
{
  vars:
      # only_if defaults to "any" when the entry doesn't carry one.
      "only_if[$(load.idx)]"
        string => "$(load.inv[services][$(load.idx)][only_if])",
        ifvarclass => "has_only_if_$(load.idx)";

      "only_if[$(load.idx)]"
        string => "any",
        ifvarclass => "!has_only_if_$(load.idx)";

  classes:
      # Defines has_nginx, has_node_exporter, ... regardless of source casing.
      "has_$(load.canon[$(load.idx)])" expression => "any";

      "run_$(load.canon[$(load.idx)])"
        expression => "has_$(load.canon[$(load.idx)]).!maintenance.($(only_if[$(load.idx)]))";

  methods:
      "nginx"         usebundle => svc_nginx,         ifvarclass => "run_nginx";
      "postgresql"    usebundle => svc_postgresql,    ifvarclass => "run_postgresql";
      "node_exporter" usebundle => svc_node_exporter, ifvarclass => "run_node_exporter";
      "log_shipper"   usebundle => svc_log_shipper,   ifvarclass => "run_log_shipper";
      "backup_agent"  usebundle => svc_backup_agent,  ifvarclass => "run_backup_agent";
      "redis"         usebundle => svc_redis,         ifvarclass => "run_redis";
}

###############################################################################
# Service bundle stubs
###############################################################################
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

`inventory.json` (the example from the prompt, used for the `has_postgresql` reference in some `only_if` expressions even though no host runs it here):

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

Running `cf-agent -K -f ./policy.cf` against this produces `CONFIGURED: svc_nginx`, `svc_node_exporter`, and `svc_log_shipper` (today is a weekday) — `svc_backup_agent` correctly stays off since no host in this sample runs postgresql. I also verified `NGINX`/`postgresql`/`Node-exporter` (arbitrary mixed casing) resolve and run correctly, and that `"maintenance": true` suppresses every service bundle.