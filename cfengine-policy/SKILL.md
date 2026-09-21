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

**Promise type ordering** (agent bundles evaluate in this order, not source order):
vars, classes, files, packages, guest_environments, methods, processes, services,
commands, storage, databases, reports

Override with `body file control { evaluation_order => "top_down"; }` (3.27+, per-file).

## Variable Types

- `string` -- `"value"` or function returning string
- `slist` -- `{ "a", "b", "c" }` or function returning list
- `int`, `real` -- numeric
- `data` -- JSON containers via `parsejson()`, `readjson()`, `mergedata()`

Variables expand with `$(varname)` or `${varname}`. Qualified: `$(bundle.var)`.
Container access: `$(data[key])`, `$(data[0])`, `$(data[key][subkey])`.

## Classes (Conditions)

Classes are booleans that gate promise evaluation.

- Operators: `.` (AND), `|` (OR), `!` (NOT), `()` grouping
- Defined by: `classes:` promises, function results, hard classes (OS, time, hostname)
- Scopes: `bundle` (default in agent), `namespace` (default in common)
- Namespace-qualified: `namespace:classname`

**Hard classes** (always available): OS (`linux`, `windows`, `darwin`), architecture
(`x86_64`), time (`Monday`, `September`, `Day21`, `Hr14`, `Min30`), hostname.

## Augments (def.json)

```json
{
  "inputs": ["services/extra.cf"],
  "vars": {
    "my_var": "value",
    "my_list": ["a", "b"]
  },
  "classes": {
    "my_class": ["any"],
    "conditional": ["linux.!redhat"]
  }
}
```

Place at policy root or use `"augments"` key for recursive includes.

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

**Inventory variables (reported to hub):**
```cfengine3
vars:
    "_value" string => "something",
      meta => { "inventory", "attribute_name=My Attribute" };
```

**Mustache templates:**
```cfengine3
files:
    "/etc/config"
      edit_template_string => "server={{vars.def.server}}$(const.n)",
      template_method => "inline_mustache",
      template_data => '{}';
```
With no explicit `template_data`, `datastate()` (all vars + classes) is used.
For performance, pass explicit `template_data` when you only need a few values.

## Common Mistakes

1. **`edit_line` is a bundle reference**, not inline braces
2. **No `inventory:` promise type** -- use `vars:` with `meta => { "inventory", ... }`
3. **`body common control` only in `promises.cf`** -- use `body file control` elsewhere
4. **Commands with pipes/redirects need `contain => in_shell`**
5. **Class names:** alphanumeric + underscore only. Use `canonify()` for dynamic names
6. **CFEngine regexes are anchored** (full match). `"foo"` does not match `"foobar"`
7. **`strlen()` does not exist** -- the function is `string_length()`
8. **`content =>` makes no backups** -- unlike `edit_line`/templates
9. **Policy files must be mode 600** (not group/world writable) or cf-agent refuses them

## 3-Pass Evaluation

Each bundle is evaluated in 3 passes. Classes defined in pass 1 become available
to vars in pass 2. This is important:

- **The guard latches, not the variable.** An unguarded `vars:` promise is
  recomputed each pass. A guarded one that fires on pass 1 and whose guard
  becomes false on pass 2 retains the pass-1 value.
- **Never use `if => not(isvariable(...))` to "optimize"** -- it latches the
  wrong pass-1 value.
- **Use `difference()` for negative lists** instead of negated class guards
  which capture false positives from pass 1.

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
# Syntax check
cf-promises -cf ./policy.cf

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
