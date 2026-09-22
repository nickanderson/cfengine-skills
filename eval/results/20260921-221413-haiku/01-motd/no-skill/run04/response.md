## Summary

I've created a CFEngine policy to manage the message of the day with 3 independent configurable variables:

### **motd.cf** (Main Policy)

```cfengine3
bundle agent manage_motd
{
  meta:
    "description" string => "Manage system message of the day (MOTD)";
    "version" string => "1.0";

  vars:
    any::
      "motd_enabled" string => "true",
        meta => { "source=augments" };
      "motd_file" string => "/etc/motd",
        meta => { "source=augments" };
      "motd_content" string => "Welcome to the system!",
        meta => { "source=augments" };

  classes:
    any::
      "motd_active" expression => strcmp("$(motd_enabled)", "true");

  files:
    motd_active::
      "$(motd_file)"
        create => "true",
        edit_line => set_motd_content("$(motd_content)"),
        perms => mog("0644", "root", "root"),
        comment => "Manage the system message of the day";

  reports:
    motd_active::
      "MOTD: Policy is managing $(motd_file) with configured content"
        ifvarclass => "verbose";
    !motd_active::
      "MOTD: Policy is disabled (motd_enabled=false)"
        ifvarclass => "verbose";
}

bundle edit_line set_motd_content(content)
{
  delete_lines:
    any::
      ".*";

  insert_lines:
    any::
      "$(content)";
}
```

### **The 3 Configurable Variables**

1. **`motd_enabled`** - Enable/disable MOTD management (default: "true")
2. **`motd_file`** - Path to the MOTD file (default: "/etc/motd")
3. **`motd_content`** - The message content to display (default: "Welcome to the system!")

### **def.json** (Standard Configuration)

```json
{
  "classes": {
    "any": [
      "inventory_cmdb"
    ]
  },
  "vars": {
    "manage_motd": {
      "motd_enabled": "true",
      "motd_file": "/etc/motd",
      "motd_content": "Welcome to the system!\n\nThis is a managed system."
    }
  }
}
```

All variables are overridable via augments, allowing you to customize MOTD behavior across different systems without modifying the base policy.