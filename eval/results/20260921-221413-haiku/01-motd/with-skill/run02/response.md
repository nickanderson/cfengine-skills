## CFEngine MOTD Management Policy

I've created a complete MOTD management policy with 3 independent configurable variables. Both files have been validated with `cf-promises` and are ready to use.

### **motd.cf** — The policy bundle

```cfengine3
body common control
{
  bundlesequence => { "motd" };
}

bundle agent motd
{
  vars:
      # Tunable via augments (def.json) - Enable/disable MOTD management
      "enabled"
        string => ifelse(isvariable("def.motd_enabled"),
                         "$(def.motd_enabled)",
                         "true");

      # Tunable via augments (def.json) - Path to the MOTD file
      "path"
        string => ifelse(isvariable("def.motd_path"),
                         "$(def.motd_path)",
                         "/etc/motd");

      # Tunable via augments (def.json) - Content of the MOTD
      "content"
        string => ifelse(isvariable("def.motd_content"),
                         "$(def.motd_content)",
                         "Welcome to $(sys.hostname)$(const.n)");

  reports:
    "motd_enabled_false"::
      "MOTD management is disabled";

  files:
    motd_enabled_true::
      "$(path)"
        create => "true",
        edit_line => set_motd_content("$(motd.content)"),
        perms => mog("644", "root", "root");
}

bundle edit_line set_motd_content(content)
{
  delete_lines:
      ".*";

  insert_lines:
      "$(content)";
}

body perms mog(mode, user, group)
{
  mode => "$(mode)";
  owners => { "$(user)" };
  groups => { "$(group)" };
}
```

### **def.json** — Augments with default values

```json
{
  "vars": {
    "motd_enabled": "true",
    "motd_path": "/etc/motd",
    "motd_content": "Welcome to $(sys.hostname)\n\nPlease note: Unauthorized access is prohibited.\n"
  }
}
```

### The 3 Independent Variables

1. **`motd_enabled`** — Controls whether MOTD management is active (true/false). When false, the policy reports that management is disabled.

2. **`motd_path`** — Specifies the file path for the MOTD (default: `/etc/motd`). Can be overridden to manage alternative locations.

3. **`motd_content`** — Contains the actual MOTD text displayed to users. Supports `$(sys.hostname)` expansion and newline escape sequences.

### Customization

Override any variable in `def.json`:
```json
{
  "vars": {
    "motd_enabled": "false",
    "motd_path": "/var/motd",
    "motd_content": "Custom MOTD message\n"
  }
}
```

The policy follows CFEngine conventions using `isvariable()` + `ifelse()` pattern to safely check for augment-defined variables with sensible fallback defaults.