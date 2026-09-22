---
name: cfengine-policy
description: >
  CFEngine policy language reference for writing, reviewing, and debugging
  .cf files, def.json augments, and cfbs projects. Use when working with
  CFEngine policy.
allowed-tools: Bash(${CLAUDE_SKILL_DIR}/../scripts/ensure-docs.sh)
---

```!
${CLAUDE_SKILL_DIR}/../scripts/ensure-docs.sh
```

# CFEngine Policy Reference

## Introspection

The installed CFEngine binary is the authoritative syntax reference. Use it
before relying on memorized knowledge:

```bash
# Machine-readable language spec (JSON)
cf-promises --syntax-description=json | jq '.bundleTypes | keys'         # bundle types
cf-promises --syntax-description=json | jq '.promiseTypes | keys'        # promise types
cf-promises --syntax-description=json | jq '.promiseTypes.files.attributes | keys'  # attributes for files
cf-promises --syntax-description=json | jq '[.promiseTypes.files.attributes | to_entries[] | select(.value.type == "body") | .key]'  # body-typed attributes
cf-promises --syntax-description=json | jq '.bodyTypes.perms.attributes | keys'     # attributes in body perms
cf-promises --syntax-description=json | jq '.functions | keys'           # all built-in functions
cf-promises --syntax-description=json | jq '.functions.readjson'         # function signature

# Validate policy
cf-promises -cf policy.cf        # syntax + semantic check
cf-promises --full-check policy.cf  # thorough check including unused vars
```

Search the documentation checkout for detailed explanations:
- `content/reference/promise-types/` -- promise type docs
- `content/reference/functions/` -- function reference
- `content/reference/language-concepts/` -- evaluation, scoping, classes
- `content/reference/special-variables/` -- sys.*, this.*, const.*

## Core Syntax

```cfengine3
bundle <type> <name>(<params>)
{
  <promise_type>:
    <class_expression>::
      "<promiser>"
        <attribute> => <value>,
        <attribute> => <body>;
}

body <type> <name>(<params>)
{
  <attribute> => <value>;
}
```

**Bundle types:** agent, common, edit_line, edit_xml, server, monitor

**Promise type ordering** depends on `evaluation_order` and the bundle type.
The default is Normal Order, which evaluates by promise type, not source order.

**agent** bundles: vars, classes, files, packages, guest_environments, methods,
processes, services, commands, storage, databases, reports, then any custom
promise types last (in source order)

**common** bundles: vars, classes, reports

**edit_line** bundles: vars, classes, delete_lines, insert_lines, field_edits,
replace_patterns, reports

**edit_xml** bundles: vars, classes, build_xpath, delete_tree, insert_tree,
delete_attribute, set_attribute, delete_text, set_text, insert_text, reports

**server** bundles: vars, classes, access, roles, reports

**monitor** bundles: vars, classes, measurements, reports

Override with `body file control { evaluation_order => "top_down"; }` (3.27+,
per-file, affects only bundles defined in that file).

## Variable Types

- `string` -- `"value"` or function returning string
- `slist` -- `{ "a", "b", "c" }` or function returning list
- `int`, `real` -- numeric
- `data` -- JSON containers via `parsejson()`, `readjson()`, `mergedata()`

Variables expand with `$(varname)` or `${varname}`. Qualified: `$(bundle.var)`.
Container access: `$(data[key])`, `$(data[0])`, `$(data[key][subkey])`.

## Classes (Conditions)

Classes are booleans that guard promise evaluation.

- Operators: `.` (AND), `|` (OR), `!` (NOT), `()` grouping
- Defined by: Hard classes automatically via the agents system discovery initialization (OS, time, hostname), `classes:` promises, or as the result of promise executions via a `classes` body, )
- Scopes: `bundle` (default in agent bundles), `namespace` (default in common bundles and result of promise via classes body)
- Namespace-qualified: `namespace:classname`

**Hard classes** (always available): OS (`linux`, `windows`, `darwin`), architecture
(`x86_64`), time (`Monday`, `September`, `Day21`, `Hr14`, `Min30`), hostname.

## Augments

Augments are JSON data files that define variables and classes before any
policy is parsed. The augments system consists of:
- `def.json` -- placed adjacent to the policy entry point
- Additional augments files loaded recursively via the `"augments"` key
- `host_specific.json` -- CMDB data, managed by CFEngine Enterprise

**Loading order:**
1. `host_specific.json` (`$(sys.workdir)/data/`) -- CMDB data, loaded first.
   Vars tagged `source=cmdb`, cannot be overridden by later augments (policy can)
2. `def_preferred.json` (if present, replaces `def.json`;
   disable with `--ignore-preferred-augments`)
3. `def.json` (adjacent to policy entry). Vars tagged `source=augments_file`
4. Recursive includes via `"augments"` key (merged with `mergedata()` semantics)

**Default scope** depends on the source:

| | `def.json` (and includes) | `host_specific.json` |
|---|---|---|
| Variables | `default:def` -- `$(def.varname)` | `data:variables` -- `$(data:variables.varname)` |
| Classes | `default` namespace | `data` namespace -- `data:classname` |
| Tags | `source=augments_file` | `source=cmdb` |

Note: `host_specific.json` requires the `::` suffix on class expressions
(e.g. `["any::"]` not `["any"]`).

Augments are processed before policy evaluation, so class definitions can only
use hard classes (OS, architecture, hostname) and persistent classes. Business
logic classes defined in policy won't be available yet -- if you need to gate
augments on them, define those classes persistently so they survive between
agent runs.

### Variables

Two forms. Both can appear in the same file; if both define the same variable,
`variables` wins.

Compact (`vars`) -- simple key-value, supports namespace/bundle targeting (3.18+):
```json
{
  "vars": {
    "my_var": "value",
    "my_list": ["a", "b"],
    "MyBundle.scoped_var": "targeted to MyBundle"
  }
}
```

Expressive (`variables`, 3.18+) -- adds `comment` and `tags` metadata:
```json
{
  "variables": {
    "my_var": {
      "value": "something",
      "comment": "Why this value exists",
      "tags": ["my_tag"]
    }
  }
}
```

### Classes

Compact -- list of regexes matching hard classes, or class expressions
(suffixed with `::` to distinguish from regexes):
```json
{
  "classes": {
    "my_class": ["any::"],
    "webserver": ["server[34]", "debian.*"],
    "production_linux": ["linux.prod_dc1::"]
  }
}
```

Expressive (3.18+) -- dict with `class_expressions` or `regular_expressions`,
plus `comment` and `tags`:
```json
{
  "classes": {
    "production": {
      "class_expressions": ["prod_dc1.!staging::"],
      "comment": "Hosts in production DC1 that are not staging",
      "tags": ["environment"]
    },
    "rhel_family": {
      "regular_expressions": ["redhat.*", "centos.*"],
      "tags": ["os_family"]
    }
  }
}
```

Classes from augments are tagged `source=augments_file`.

### Other keys

```json
{
  "inputs": ["services/extra.cf"],
  "augments": ["path/to/other.json"]
}
```

`inputs` adds policy files. `augments` recursively loads and merges other
augments files.

## Augments Tunables Pattern

To make a policy variable configurable via augments
(def.json/host_specific.json), the policy must be **instrumented** to use the
pre-defined variables (usually providing a default policy value if the variable
is not defined).

The `def.json` at the policy root defines variables in the `def` bundle of the
`default` namespace:

```cfengine3
bundle agent motd
{
  vars:
      # Tunable via augments -- policy reads from def, falls back to default
      "organization"
        string => ifelse(isvariable("def.motd_organization"),
                         "$(def.motd_organization)",
                         "Acme Corp");

      "support_contact"
        string => ifelse(isvariable("def.motd_support_contact"),
                         "$(def.motd_support_contact)",
                         "help@acme.com");
}
```

The corresponding `def.json` to override:

```json
{
  "vars": {
    "motd_organization": "Globex",
    "motd_support_contact": "ops@globex.com"
  }
}
```

**Key rules:**
- When working across namespaces, fully qualify variable references with
  `namespace:bundle.var` (e.g. `default:def.motd_organization`). Within the
  `default` namespace (the typical case), `def.varname` works fine
- `def.json` `vars` defines variables in `default:def` -- the key in JSON is
  just the variable name (e.g. `motd_organization`), not the qualified form
- Without instrumentation in the policy (the `isvariable` + `ifelse` pattern
  above), augments variables exist in `def` but nothing reads them -- they
  have no effect on your bundle's variables

## Key Patterns

**Prefer `ifelse()` over multiple class-guarded vars:**
```cfengine3
vars:
    "_pkg" string => ifelse(
      "redhat", "httpd",
      "debian", "apache2",
      "unknown");
```

**File content from command output:**
```cfengine3
files:
    "/var/cache/data.json"
      content => execresult("/usr/bin/tool --export", "noshell", "stdout");
```

**Capture command output + return code as data container:**
```cfengine3
vars:
    "_result" data => execresult_as_data("/usr/bin/tool --check", "noshell", "both");
    # _result[exit_code] = return code, _result[output] = captured streams
    # 3rd arg controls what goes into output: "stdout", "stderr", or "both"
```

**Inventory variables (reported to hub):**
```cfengine3
vars:
    "_value" string => "something",
      meta => { "inventory", "attribute_name=My Attribute" };
```

**Mustache templates -- always pass explicit `template_data`:**
```cfengine3
vars:
    "_data" data => parsejson('{ "server": "$(def.server)", "port": "$(def.port)" }');
files:
    "/etc/config"
      edit_template_string => "server={{server}}:{{port}}$(const.n)",
      template_method => "inline_mustache",
      template_data => @(_data);
```
To include classes for mustache conditionals (`{{#is_production}}...{{/is_production}}`),
add them as boolean keys in the data container:
```cfengine3
vars:
    "_td" data => mergedata(_data,
      format('{ "is_production": %s, "is_linux": %s }',
        ifelse("production", "true", "false"),
        ifelse("linux", "true", "false")));
```
Or list matching classes with `classesmatching()` filtered by tag:
```cfengine3
vars:
    "_env_classes" slist => classesmatching(".*", "environment");
```
Without `template_data`, `datastate()` is used implicitly -- this serializes
every variable and class in scope and is expensive. Construct a data container
with only the values the template needs.

## Common Mistakes

1. **Policy files must be mode 600** (not group/world writable) or `cf-agent` refuses them
2. **`edit_line` is a bundle reference**, not inline braces
3. **No `inventory:` promise type** -- use `vars:` with `meta => { "inventory", ... }`
4. **`body common control` only in policy entries (`promises.cf`, `update.cf`, `standalone_self_upgrade.cf`) ** -- use `body file control` elsewhere
5. **Commands with pipes/redirects need `contain => in_shell`**
6. **Class names:** alphanumeric + underscore only. Use `canonify()` for dynamic names that can contain invalid characters.
7. **`strlen()` does not exist** -- the function is `string_length()`

## 3-Pass Evaluation

Each bundle is evaluated in 3 passes. Classes defined in pass 1 become available
to vars in pass 2. This is important:

- Variables are re-computed each pass, unless explicitly avoided. An unguarded `vars:` promise is
  recomputed each pass. A guarded one that fires on pass 1 and whose guard
  becomes false on pass 2 retains the pass-1 value.
- `methods` promises evaluate the bundle in 3 passes and are not re-evaluated on subsequent passes.

## Useful Functions

Look up signatures with `cf-promises --syntax-description=json | jq '.functions.<name>'`.

Commonly needed: `readfile`, `readjson`, `parsejson`, `mergedata`, `readstringarrayidx`,
`getindices`, `getvalues`, `join`, `unique`, `difference`, `length`, `maplist`,
`classesmatching`, `variablesmatching`, `findfiles`, `lsdir`, `fileexists`,
`regcmp`, `regex_replace`, `canonify`, `ifelse`, `strcmp`, `isvariable`,
`strftime`, `now`, `eval`, `format`, `string_mustache`, `execresult`, `returnszero`,
`sort`, `nth`, `every`, `some`, `none`, `filter`.

## Testing and Validation

```bash
# Syntax + semantic check
cf-promises -cf ./policy.cf

# Lint (checks for undefined promise types, bundles, bodies, functions)
cfengine lint ./policy.cf

# Run standalone policy
cf-agent -KIf ./policy.cf

# Show evaluated variables
cf-agent -KIf ./policy.cf --show-evaluated-vars=mybundle

# Show defined classes
cf-agent --show-evaluated-classes

# Profile promise evaluation times
cf-agent -K -p -f ./policy.cf
```

For details on any topic, search the documentation checkout at the path shown above.
