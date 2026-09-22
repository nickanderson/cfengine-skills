# motd policy

Manages `/etc/motd` from three independent, augments-configurable variables.

| Augments key   | Policy variable | Default                                |
|----------------|-----------------|----------------------------------------|
| `motd_banner`  | `motd.banner`   | `Welcome to $(sys.uqhost)`             |
| `motd_message` | `motd.message`  | `Authorized use only. ...`             |
| `motd_contact` | `motd.contact`  | `root@$(sys.fqhost)`                   |

Each is read with `default()`, so any subset may be set in `def.json`; unset
ones fall back to the value in the policy.

## Standalone test

    cf-agent -KIf ./standalone.cf          # needs root to write /etc/motd
    cf-agent -KIf ./standalone.cf -D DEBUG # print the effective values

## Deployment in the Masterfiles Policy Framework

1. Copy `motd.cf` to `masterfiles/services/motd.cf`.
2. Add it to the policy, either in `promises.cf`:

       inputs => { ..., "services/motd.cf" };
       bundlesequence => { ..., "motd" };

   or from `masterfiles/def.json`:

       {
         "inputs": [ "services/motd.cf" ],
         "variables": {
           "control_common_bundlesequence_end": [ "motd" ],
           "motd_banner": "...",
           "motd_message": "...",
           "motd_contact": "..."
         }
       }

3. Merge the `variables` block of the `def.json` here into
   `masterfiles/def.json`. Per host or per group overrides can be layered with
   the augments `augments` key, e.g.
   `"augments": [ "/var/cfengine/host_def.json" ]`.

Requires CFEngine 3.18 or newer (`edit_template_string` with
`template_method => "inline_mustache"`). Verified against CFEngine 3.27.1.
