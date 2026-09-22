Done! I've created a CFEngine policy for managing the message of the day with 3 independent, configurable variables.

## Summary

**motd.cf** — The main CFEngine policy bundle that:
- Defines 3 variables: `motd_title`, `motd_body`, and `motd_footer`
- Each variable checks if it's been defined in augments (def.json) via `def.*`, otherwise uses sensible defaults
- Combines the three variables into `motd_content`
- Manages `/etc/motd` with the constructed content
- Includes reporting to display the configuration in verbose mode

**def.json** — An example augments file showing how to override the 3 variables with custom values

The three variables are truly independent and can be customized separately:
1. **motd_title** — Header/welcome message
2. **motd_body** — Main message content
3. **motd_footer** — Footer with contact/support info

## Complete Policies

**motd.cf:**
```cf3
##############################################################################
#
# motd.cf - CFEngine policy to manage message of the day
#
# This policy manages /etc/motd using three configurable variables that can
# be customized via augments (def.json)
#
##############################################################################

bundle agent motd_management
{
  vars:
    # Variable 1: MOTD title/header line
    "motd_title"
      string => ifelse(isvariable("def.motd_title"), 
                      "$(def.motd_title)", 
                      "Welcome to $(sys.hostname)"),
      policy => "free";

    # Variable 2: MOTD main message/body
    "motd_body"
      string => ifelse(isvariable("def.motd_body"), 
                      "$(def.motd_body)", 
                      "This is a managed system. Unauthorized access is prohibited."),
      policy => "free";

    # Variable 3: MOTD footer/contact information
    "motd_footer"
      string => ifelse(isvariable("def.motd_footer"), 
                      "$(def.motd_footer)", 
                      "For support, contact your system administrator."),
      policy => "free";

    # Construct the complete MOTD content from the three variables
    "motd_content"
      string => "$(motd_title)
$(motd_body)
$(motd_footer)
",
      policy => "free";

  files:
    "/etc/motd"
      content => "$(motd_content)",
      create => "true",
      perms => mog("644", "root", "root"),
      edit_defaults => std_defs;

  reports:
    verbose::
      "MOTD Policy: Managing /etc/motd with the following configuration:"
        comment => "Display policy configuration in verbose mode";
      "  Title: $(motd_title)"
        comment => "Show configured title";
      "  Body: $(motd_body)"
        comment => "Show configured message body";
      "  Footer: $(motd_footer)"
        comment => "Show configured footer";
}

##############################################################################
# Main bundle to invoke MOTD management
##############################################################################

body file control
{
  namespace => "cfengine_core";
}

bundle agent main
{
  methods:
    "Run MOTD Management"
      usebundle => motd_management;
}
```

**def.json:**
```json
{
  "vars": {
    "motd_title": "System Access Notice",
    "motd_body": "This is a production system. All activities are logged and monitored. Unauthorized access attempts will be prosecuted to the fullest extent of the law.",
    "motd_footer": "For issues, contact: admin@example.com | Last updated: 2026-09-21"
  }
}
```