CFEngine MOTD (Message of the Day) Policy
==========================================

OVERVIEW
--------
This policy provides a complete solution for managing the system message of the day (MOTD)
with three independent, configurable variables.

POLICY FILES
------------
1. motd.cf        - Main CFEngine policy
2. def.json       - Augments file with default variable values

CONFIGURABLE VARIABLES
----------------------
The policy defines 3 independent variables in the "motd_settings" bundle:

1. enable (string)
   - Controls whether MOTD management is active
   - Default: "true"
   - Values: "true" or "false"
   - Example: "false" to disable MOTD management

2. motd_file (string)
   - Path to the MOTD file to be managed
   - Default: "/etc/motd"
   - Values: Any valid file path
   - Example: "/etc/motd.custom" to use custom location

3. motd_content (string)
   - The actual content to write to the MOTD file
   - Default: Welcome message with hostname and security notice
   - Values: Any multi-line text string
   - Example: Custom welcome message with company branding

USAGE
-----
1. Place motd.cf in your CFEngine policies directory
2. Place def.json in your CFEngine augments directory (typically /var/cfengine/inputs/augments)
3. Edit def.json to customize the variables for your environment
4. CFEngine will load the augments and apply the policy on its next run

CONFIGURATION EXAMPLE
---------------------
To customize the MOTD, edit the "motd_settings" section in def.json:

{
  "motd_settings": {
    "enable": "true",
    "motd_file": "/etc/motd",
    "motd_content": "Welcome to our servers\n\nManaged by CFEngine\n"
  }
}

POLICY BEHAVIOR
---------------
- Creates the MOTD file if it doesn't exist
- Sets file permissions to 644 (rw-r--r--) owned by root
- Replaces MOTD content with the configured value
- Can be disabled by setting enable to "false"
- Generates reports on each run showing action taken

REQUIREMENTS
------------
- CFEngine 3.6+ or later
- Root privileges to manage /etc/motd
- Standard library ($(sys.libdir)/stdlib.cf)
