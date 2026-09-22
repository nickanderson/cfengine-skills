# motd

Manages the content of `/etc/motd` from a mustache template.

## Files

| File | Purpose |
| --- | --- |
| `motd.cf` | The `motd` bundle, the policy itself |
| `templates/motd.mustache` | The template rendered into `/etc/motd` |
| `def.json` | Example augments, this is where you set the content |
| `promises.cf` | Stand alone entry point, only for testing |

## The three variables

All three are optional. Each one falls back to a built in default when it is
not defined, so the policy is safe to run without any augments.

| Augments key | Type | Default |
| --- | --- | --- |
| `motd_banner` | string | `Welcome to $(sys.fqhost) ($(sys.flavor) $(sys.arch))` |
| `motd_notices` | list of strings | two generic notices |
| `motd_contact` | string | `root@$(sys.fqhost)` |

They are independent, set one, two, or all three.

## Testing

```
cf-agent -KI -f ./promises.cf
```

## Using it with the Masterfiles Policy Framework

1. Drop `motd.cf` into `masterfiles/services/` and the template into
   `masterfiles/templates/`, adjusting the `template` variable if you move it.
2. Add it to the inputs and call it, for example in
   `services/autorun/` (the bundle carries the `autorun` tag ready via `meta`), or
   explicitly from `services/main.cf`:

   ```cfengine3
   methods:
       "motd" usebundle => motd;
   ```

3. Put your content in the site level `def.json` under `variables`.

## Note for Debian and Ubuntu

On those platforms the login banner is usually assembled by `pam_motd` from
`/etc/update-motd.d/` and `/etc/motd`. This policy manages the static
`/etc/motd` part. If `/etc/motd` is a symlink on your hosts (check with
`ls -l /etc/motd`), point `motd_file` at the real file instead.
