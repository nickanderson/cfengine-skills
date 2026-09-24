# CFEngine MOTD Policy

This policy manages the Message of the Day (MOTD) on Linux systems. It provides three independent, configurable variables that control the behavior of MOTD management.

## Policy Overview

The policy defines a bundle named `motd` that manages the MOTD file with configurable options via augments (def.json).

## Configurable Variables

The policy uses three independent variables, all of which can be configured via `def.json` augments:

### 1. `motd_enabled` (default: "true")
- **Type**: String (boolean-like: "true" or "false")
- **Purpose**: Controls whether MOTD management is enabled
- **Usage**: Set in `def.motd_enabled`
- **Example**: `"motd_enabled": "true"`

### 2. `motd_file` (default: "/etc/motd")
- **Type**: String (file path)
- **Purpose**: Specifies the location of the MOTD file
- **Usage**: Set in `def.motd_file`
- **Example**: `"motd_file": "/etc/motd"`

### 3. `motd_content` (default: "Welcome to the system")
- **Type**: String (multi-line allowed)
- **Purpose**: Specifies the actual message content to display
- **Usage**: Set in `def.motd_content`
- **Example**: `"motd_content": "Welcome to Production Server\n\nContact: admin@example.com"`

## Usage

### Basic Configuration

Add the policy to your CFEngine inputs and configure the variables in your `def.json`:

```json
{
  "vars": {
    "motd_enabled": "true",
    "motd_file": "/etc/motd",
    "motd_content": "Welcome to the system\n\nUnauthorized access is prohibited."
  }
}
```

### Disabling MOTD Management

To disable MOTD management, set `motd_enabled` to "false":

```json
{
  "vars": {
    "motd_enabled": "false"
  }
}
```

### Custom MOTD Location

To use a custom MOTD file location:

```json
{
  "vars": {
    "motd_file": "/var/motd_custom",
    "motd_content": "Custom MOTD message"
  }
}
```

## How It Works

1. The policy reads values from `def.motd_enabled`, `def.motd_file`, and `def.motd_content`
2. If these variables are not defined, it uses sensible defaults
3. If `motd_enabled` is set to "true", it creates/updates the MOTD file
4. The file content is completely replaced with the specified `motd_content`
5. The `edit_line` bundle `insert_motd_content` removes all existing lines and inserts the new content

## Integration Example

Include this policy in your CFEngine main policy file:

```cfengine3
body file control
{
  inputs => {
    "motd.cf"
  };
}

bundle agent main
{
  methods:
    "any" usebundle => motd;
}
```

## Debug Output

Enable debug mode to see variable values:

```
cf-agent -d -f motd.cf
```

This will display the resolved values of all three configuration variables.
