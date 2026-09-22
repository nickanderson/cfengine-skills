# motd

Manages `/etc/motd` from three independent variables, each overridable via
augments (`def.json`):

| Variable                   | Default                     | Purpose                    |
| -------------------------- | --------------------------- | -------------------------- |
| `default:def.motd_path`    | `/etc/motd`                 | Path to the motd file      |
| `default:def.motd_banner`  | `Welcome to $(sys.fqhost)`  | Banner / first line        |
| `default:def.motd_contact` | `root@$(sys.fqhost)`        | Contact line               |

## Usage

Standalone:

    cf-agent --no-lock --inform --file ./motd.cf

Integrated into masterfiles: copy `motd.cf` into `services/` (or similar), add
it to `inputs` in `promises.cf`, add `"motd";` to a `methods:` promise in
`bundle agent main` (or tag the bundle for autorun), and merge the `variables`
section of `def.json` into your masterfiles `def.json`.

Because the variables are read with `isvariable()` fallbacks, the policy works
with or without an augments file present.
