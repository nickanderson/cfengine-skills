# CFEngine MOTD Management Policy

This policy manages the system message of the day (motd) file with three independent, configurable variables.

## Variables

The policy defines 3 variables in the `motd` bundle that can be overridden via augments in `def.json`:

1. **motd_file** - The path to the motd file (default: `/etc/motd`)
2. **motd_content** - The message of the day content (default: `Welcome to the system`)
3. **motd_enabled** - Enable/disable motd management (default: `true`)

## Usage

### Default Configuration
With no augments, the policy uses built-in defaults:
- File: `/etc/motd`
- Content: `Welcome to the system`
- Enabled: `true`

### Custom Configuration via Augments
Place the `def.json` file in your policy directory to override defaults. The `def.json` structure is:

```json
{
  "vars": {
    "motd": {
      "motd_file": "/etc/motd",
      "motd_content": "Your custom message here\nMultiple lines supported",
      "motd_enabled": "true"
    }
  }
}
```

## Policy Behavior

- When `motd_enabled` is set to `"true"`, the policy will:
  - Create or update the motd file specified in `motd_file`
  - Set permissions to 644 (readable by all)
  - Populate it with the content from `motd_content`
  - Log activity to `/var/log/cfengine_motd.log`

- When `motd_enabled` is set to `"false"`, the policy reports that management is disabled and takes no action

## Integration

Include this bundle in your main policy:

```cf
body common control {
  bundlesequence => { "motd" };
}

bundle agent motd {
  # ... policy content ...
}
```

Or call it from an existing bundle:

```cf
methods:
  "motd" usebundle => motd;
```
